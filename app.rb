require 'bundler'
Bundler.require

STDOUT.sync = true

class App < Sinatra::Base

  configure :development do
    require "sinatra/reloader"
    register Sinatra::Reloader
  end

  configure do
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
  end

  get "/" do
    heroku = Heroku::API.new(:api_key => request.env['bouncer.token']) 
    @apps = heroku.get_apps.body.sort{|x,y| x["name"] <=> y["name"]}
    slim :index
  end

  get '/app/:id' do
    heroku = Heroku::API.new(:api_key => request.env['bouncer.token']) 
    @app = heroku.get_app(params[:id]).body
    @ps = heroku.get_ps(params[:id]).body.select{|x| x["process"].include?("web.")}

    config = heroku.get_config_vars(params[:id]).body
    @concurrency = config["UNICORN_WORKERS"].to_i || config["WEB_CONCURRENCY"].to_i || 1

    slim :app
  end

  get "/log/:id", provides: 'text/event-stream' do
    @heroku = Heroku::API.new(:api_key => request.env['bouncer.token']) 
    url = @heroku.get_logs(params[:id], {'tail' => 1, 'num' => 5000}).body

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

          ps = matches[3].split('.').first
          data = Hash[ matches[4].split(" ").map{|j| j.split("=")} ]

          parsed_line = {}

          if ps == "router"
            parsed_line = {
              "requests" => 1,
              "response_time" => data["service"].to_i,
              "status" => "#{data["status"][0]}xx"
            }
            parsed_line["error"] = data["code"] if data["at"] == "error"
          elsif data.fetch("measure","").include?("web.memory_total")
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

end