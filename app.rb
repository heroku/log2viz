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
    def data(hash)
      hash.keys.each_with_object({}){ |key, data_hash| data_hash["data-#{key}"] = hash[key] }
    end

    def tooltip(content)
      slim :_tooltip, locals: {content: content}
    end
  end

  before do
    if request.env['bouncer.user']
      @user = request.env['bouncer.user']
    end
  end

  get "/" do
    heroku = Heroku::API.new(:api_key => request.env['bouncer.token'])
    @apps = heroku.get_apps.body.sort{|x,y| x["name"] <=> y["name"]}
    slim :index
  end

  get '/app/:id' do
    heroku = Heroku::API.new(:api_key => request.env['bouncer.token'])
    @app = heroku.get_app(params[:id]).body
    @title = params[:id]

    begin
      @ps = heroku.get_ps(params[:id]).body.select{|x| x["process"].include?("web.")}.count

      config = heroku.get_config_vars(params[:id]).body
      @concurrency = (config["UNICORN_WORKERS"] || config["WEB_CONCURRENCY"] || params[:concurrency] || 1).to_i
    rescue
      @ps = 1
      @concurrency =  (params[:concurrency] || 1).to_i
      flash.now[:error] = "Process data not available"
    end

    slim :app
  end

  get "/log/:id", provides: 'text/event-stream' do
    @heroku = Heroku::API.new(:api_key => request.env['bouncer.token'])
    url = @heroku.get_logs(params[:id], {'tail' => 1, 'num' => 5000}).body
    puts url

    stream :keep_open do |out|
      # Keep connection open on cedar
      EventMachine::PeriodicTimer.new(15) { out << "\0" }
      http = EventMachine::HttpRequest.new(url, keepalive: true, connection_timeout: 0, inactivity_timeout: 0).get

      out.callback do
        puts "callback: closing"
        out.close
      end
      out.errback do
        puts "errback: closing"
        out.close
      end

      buffer = ""
      http.stream do |chunk|
        buffer << chunk
        while line = buffer.slice!(/.+\n/)
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
    slim :"404"
  end

  error do
    @title = "Oops"
    slim :"500"
  end

end
