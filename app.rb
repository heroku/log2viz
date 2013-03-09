require 'bundler'
Bundler.require

STDOUT.sync = true

class App < Sinatra::Base

  configure :development do
    require "sinatra/reloader"
    register Sinatra::Reloader
  end

  helpers do
    def data(hash)
      hash.keys.each_with_object({}){ |key, data_hash| data_hash["data-#{key}"] = hash[key] }
    end
  end

  get "/" do
    @heroku = Heroku::API.new(:api_key => request.env['bouncer.token']) 
    @apps = @heroku.get_apps.body
    slim :index
  end

  get '/app/:id' do
    slim :app
  end

  get "/log/:id", provides: 'text/event-stream' do
    @heroku = Heroku::API.new(:api_key => request.env['bouncer.token']) 
    url = @heroku.get_logs(params[:id], {'tail' => 1}).body

    stream :keep_open do |out|
      # Keep connection open on cedar
      EventMachine::PeriodicTimer.new(15) { out << "\0" }
      http = EventMachine::HttpRequest.new(url).get

      out.callback { out.close }
      out.errback { out.close }

      buffer = ""
      http.stream do |chunk|
        buffer << chunk
        while line = buffer.slice!(/.+\n/)
          matches = line.force_encoding('utf-8').match(/(\S+)\s(\w+)\[(\w|.+)\]\:\s(.*)/)

          timestamp = matches[1]
          ps = matches[3]
          data = Hash[ matches[4].split(" ").map{|j| j.split("=")} ]

          parsed_line = {}
          if ps == "router"
            parsed_line = {
              "throughput" => 1,
              "response_time" => data["service"].to_i
            }
          end

          out << "data: #{parsed_line.to_json}\n\n" unless parsed_line.empty?
        end
      end
    end
  end

end