require 'faye/websocket'
require 'json'
require 'base64'
require 'net/http'
require 'uri'

#
#
#  These were constructed for the async repo maintainers, to demonstrate an inconsistancy between faye and async
#
#
namespace :faye_and_async_examples do
  task faye: :environment do
    EM.run do
      battle_state = {}
      pokemon_showdown_ws = Faye::WebSocket::Client.new(
        'wss://sim3.psim.us/showdown/websocket'
      )

      pokemon_showdown_ws.on :open do |event|
        puts 'Connected to Pokemon Showdown WebSocket'
      end

      pokemon_showdown_ws.on :message do |event|
        message = event.data

        if message.include?('|challstr|')

          challstr = message.split('|')[2..].join('|')
          uri = URI.parse('https://play.pokemonshowdown.com/api/login')
          response = Net::HTTP.post_form(
            uri,
            {
              name: ENV['POKE_USER'],
              pass: ENV['POKE_PASS'],
              challstr:
            }
          )

          body = JSON.parse(response.body.sub(']', '').strip)
          assertion = body['assertion']

          if assertion
            pokemon_showdown_ws.send("|/trn #{ENV['POKE_USER']},0,#{assertion}")
            puts "Logged in as #{ENV['POKE_USER']}"
            pokemon_showdown_ws.send('|/search gen9randombattle')
          else
            puts 'Login failed'
          end
        else
          puts message
        end

        if message.include?('|request|')
          begin
            # Extract the JSON part after the '|request|' message
            request_index = message.index('|request|')

            request_json = message[request_index + 9..-1] # Extract everything after '|request|'
            request_json.strip

            # TODO(adenta) worried this might cause problems
            # next unless request_json

            parsed_request = JSON.parse(request_json)
            battle_id = message.split('|').first.split('>').last.chomp.strip
            battle_state[:state] = parsed_request.deep_symbolize_keys!
            battle_state[:battle_id] = battle_id
          rescue JSON::ParserError
            # TODO(adenta) this is an expected empty response for now, dont want to log
          end
        end
      end

      pokemon_showdown_ws.on :error do |event|
        puts "WebSocket Error: #{event.message}"
      end

      pokemon_showdown_ws.on :close do |event|
        puts "Connection closed: #{event.code} - #{event.reason}"
      end

      EM.add_periodic_timer(5) do
        next if battle_state.empty?

        pokemon_showdown_ws.send("#{battle_state[:battle_id]}|/choose default")
      end
    end
  end

  task async: :environment do
    battle_state = {}
    endpoint = Async::HTTP::Endpoint.parse('wss://sim3.psim.us/showdown/websocket')

    Async do |task|
      Async::WebSocket::Client.connect(endpoint) do |connection|
        task.async do
          loop do
            task.sleep 1

            next if battle_state.empty?

            battle_message = Protocol::WebSocket::TextMessage.new("#{battle_state[:battle_id]}|/choose default")
            battle_message.send(connection)
            connection.flush
          end
        end

        while message_object = connection.read
          message = message_object.buffer

          if message.include?('|challstr|')

            challstr = message.split('|')[2..].join('|')
            uri = URI.parse('https://play.pokemonshowdown.com/api/login')
            response = Net::HTTP.post_form(
              uri,
              {
                name: ENV['POKE_USER'],
                pass: ENV['POKE_PASS'],
                challstr:
              }
            )

            body = JSON.parse(response.body.sub(']', '').strip)
            assertion = body['assertion']

            if assertion
              auth_message = Protocol::WebSocket::TextMessage.new("|/trn #{ENV['POKE_USER']},0,#{assertion}")
              auth_message.send(connection)
              connection.flush
              puts "Logged in as #{ENV['POKE_USER']}"
              search_message = Protocol::WebSocket::TextMessage.new('|/search gen9randombattle')
              search_message.send(connection)
              connection.flush
            else
              puts 'Login failed'
            end

          elsif message.include?('|request|')
            begin
              # Extract the JSON part after the '|request|' message
              request_index = message.index('|request|')

              request_json = message[request_index + 9..-1] # Extract everything after '|request|'
              request_json.strip

              # TODO(adenta) worried this might cause problems
              # next unless request_json

              parsed_request = JSON.parse(request_json)
              battle_id = message.split('|').first.split('>').last.chomp.strip
              battle_state[:state] = parsed_request.deep_symbolize_keys!
              battle_state[:battle_id] = battle_id
            rescue JSON::ParserError
              # TODO(adenta) this is an expected empty response for now, dont want to log
            end
          else
            puts message
          end
        end
      end
    end
  end
end
