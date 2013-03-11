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
    @apps = heroku.get_apps.body
    slim :index
  end

  get '/app/:id' do
    heroku = Heroku::API.new(:api_key => request.env['bouncer.token']) 
    @app = heroku.get_app(params[:id]).body
    slim :app
  end

  get "/log/:id", provides: 'text/event-stream' do
    @heroku = Heroku::API.new(:api_key => request.env['bouncer.token']) 
    url = @heroku.get_logs(params[:id], {'tail' => 1, 'num' => 5000, 'ps' => 'router'}).body

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

          timestamp = DateTime.parse(matches[1]).to_time.to_i
          ps = matches[3]
          data = Hash[ matches[4].split(" ").map{|j| j.split("=")} ]

          parsed_line = {
            "timestamp" => timestamp,
            "requests" => 1,
            "response_time" => data["service"].to_i,
            "status" => data["status"].to_i
          }

          out << "data: #{parsed_line.to_json}\n\n" unless parsed_line.empty?
        end
      end
    end
  end

end