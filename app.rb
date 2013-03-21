require 'bundler'
Bundler.require
require 'rack-flash'

STDOUT.sync = true

class App < Sinatra::Base
  set :raise_errors, false
  set :show_exceptions, false

  configure :development do
    require "sinatra/reloader"
    register Sinatra::Reloader
  end

  configure do
    register Sinatra::RespondWith

    use Rack::Flash
    use Stethoscope

    Stethoscope.url = "/health"
    Stethoscope.check :api do |response|
      url = "http://api.heroku.com/health"
      start = Time.now
      check = Excon.get(url)
      response[:ping] = Time.now - start
      response[:url] = url
      response[:result] = check.body
      response[:status] = check.status
    end

    Compass.add_project_configuration(File.join(File.dirname(__FILE__), 'config', 'compass.config'))
  end

  get '/stylesheets/:name.css' do
    content_type 'text/css', :charset => 'utf-8'
    scss(:"stylesheets/#{params[:name]}", Compass.sass_engine_options )
  end

  helpers do
    # Heroku API
    def api
      halt(401) unless request.env['bouncer.token']
      Heroku::API.new(:api_key => request.env['bouncer.token'])
    end

    def app(name)
      api.get_app(name).body
    rescue Heroku::API::Errors::Forbidden, Heroku::API::Errors::NotFound
      halt(404)
    end

    def web_count(name)
      api.get_ps(name).body.select{|x| x["process"].include?("web.")}.count
    rescue
      flash.now[:error] = "Process data not available."
      1
    end

    def concurrency_count(name)
      config = api.get_config_vars(name).body
      (config["UNICORN_WORKERS"] || config["WEB_CONCURRENCY"] || params[:concurrency] || 1).to_i
    rescue
      flash.now[:error] = "Configuration data not available."
      (params[:concurrency] || 1).to_i
    end

    def log_url(name)
      api.get_logs(name, {'tail' => 1, 'num' => 1500}).body
    rescue Heroku::API::Errors::Forbidden, Heroku::API::Errors::NotFound
      halt(404)
    end

    # View helpers
    def data(hash)
      hash.keys.each_with_object({}){ |key, data_hash| data_hash["data-#{key}"] = hash[key] }
    end

    def tooltip(content)
      slim :_tooltip, locals: {content: content}
    end

    def pluralize(count, singular, plural)
      count == 1 ? singular : plural
    end
  end

  before do
    if request.env['bouncer.user']
      @user = request.env['bouncer.user']
    end
  end

  get "/" do
    @apps = api.get_apps.body.sort{|x,y| x["name"] <=> y["name"]}
    slim :index
  end

  get '/app/:id' do
    name = params[:id]

    @title = name

    @app = app(name)
    @ps = web_count(name)
    @concurrency = concurrency_count(name)
    @web_processes = @concurrency * @ps

    slim :app
  end

  get "/app/:id/logs", provides: 'text/event-stream' do
    url = log_url(params[:id])

    stream :keep_open do |out|
      # Keep connection open on cedar
      EventMachine::PeriodicTimer.new(15) { out << "\0" }
      http = EventMachine::HttpRequest.new(url, keepalive: true, connection_timeout: 0, inactivity_timeout: 0).get

      out.callback do
        out.close
      end
      out.errback do
        out.close
      end

      buffer = ""
      http.stream do |chunk|
        buffer << chunk
        while line = buffer.slice!(/.+\n/)
          begin
            matches = line.force_encoding('utf-8').match(/(\S+)\s(\w+)\[(\w|.+)\]\:\s(.*)/)
            next if matches.nil? || matches.length < 5

            ps   = matches[3].split('.').first
            data = Hash[ matches[4].split(/\s+/).map{|j| j.split("=", 2)} ]

            parsed_line = {}

            if ps == "router"
              parsed_line = {
                "requests" => 1,
                "response_time" => data["service"].to_i,
                "status" => "#{data["status"][0]}xx"
              }
              parsed_line["error"] = data["code"] if data["at"] == "error"
            elsif ps == "web" && data.fetch("measure","").include?("memory_total")
              parsed_line = {
                "memory_usage" => data["val"].to_i
              }
            end

            unless parsed_line.empty?
              parsed_line["timestamp"] = DateTime.parse(matches[1]).to_time.to_i
              out << "data: #{parsed_line.to_json}\n\n"
            end
          rescue Exception => e
            puts "Error caught while parsing logs:"
            puts e.inspect
          end
        end
      end
    end
  end

  error Heroku::API::Errors::Unauthorized do
    session[:return_to] = request.url
    redirect to('/auth/heroku')
  end

  error 404 do
    @title = "Page Not Found"
    respond_to do |f|
      f.html { slim :"404" }
      f.on("*/*") { "404 App not found" }
    end
  end

  error do
    @title = "Oops"
    slim :"500"
  end

end
