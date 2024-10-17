require 'faye/websocket'
require 'json'
require 'base64'
require 'net/http'
require 'uri'
require_relative '../audio_mode_helper'

namespace :realtime do
  include AudioModeHelper

  task vibe: :environment do
    battle_state = {}
    chat_messages = []
    EM.run do
      openai_ws = Faye::WebSocket::Client.new(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01', nil, {
          headers: {
            'Authorization' => "Bearer #{ENV['OPENAI_API_KEY']}",
            'OpenAI-Beta' => 'realtime=v1'
          }
        }
      )

      pokemon_showdown_ws = Faye::WebSocket::Client.new(
        'wss://sim3.psim.us/showdown/websocket'
      )

      openai_ws.on :open do |event|
        audio_mode_puts 'Connected to OpenAI WebSocket'
        openai_ws.send({
          "type": 'session.update',
          "session": {
            "modalities": %w[
              text
              audio
            ],
            "instructions": "System settings:\nTool use: enabled.\n\nYou are an online streamer watching a game of pokemon.  \nprovide some commentary of the match as it happens. \n",
            "voice": 'alloy',
            "input_audio_format": 'pcm16',
            "output_audio_format": 'pcm16',
            "input_audio_transcription": {
              "model": 'whisper-1'
            },
            "turn_detection": nil,
            "tools": [
              {
                "type": 'function',
                "name": 'choose_move',
                "description": 'chooses a move in a game of pokemon. Only choose a move when a member of chat suggests you use it.',
                "parameters": {
                  "type": 'object',
                  "properties": {
                    "move_name": {
                      "type": 'string',
                      "description": 'the name of the move'
                    }
                  },
                  "required": [
                    'move_name'
                  ]
                }
              }
            ],
            "tool_choice": 'auto',
            "temperature": 1
          }
        }.to_json)
      end

      openai_ws.on :message do |event|
        response = JSON.parse(event.data)

        if response['type'].include? 'response.function_call_arguments.done'
          audio_mode_puts "Received message: #{response}"
        end

        if response['type'] == 'response.audio.delta' && response['delta']
          begin
            # Base64 encoced PCM packets
            audio_payload = response['delta']

            if ENV['AUDIO_MODE'] == 'true'
              STDOUT.write(Base64.decode64(audio_payload))
              STDOUT.flush
            end
          rescue StandardError => e
            audio_mode_puts "Error processing audio data: #{e}"
          end
        end
      end

      openai_ws.on :error do |event|
        audio_mode_puts "WebSocket Error: #{event.message}"
      end

      openai_ws.on :close do |event|
        audio_mode_puts "Connection closed: #{event.code} - #{event.reason}"
      end

      EM.add_periodic_timer(15) do
        openai_ws.send({
          "type": 'response.cancel'
        }.to_json)

        openai_ws.send({
          "type": 'conversation.item.create',
          "item": {
            "type": 'message',
            "role": 'user',
            "content": [
              {
                "type": 'input_text',
                "text": chat_messages.to_json
              }
            ]
          }
        }.to_json)
        chat_messages = []

        openai_ws.send({
          "type": 'response.create'
        }.to_json)

        pokemon_showdown_ws.send("#{battle_state[:battle_id]}|/timer on")
      end

      EM.add_periodic_timer(1) do
        next if battle_state.empty?

        active_pokemon = battle_state[:state][:active]&.first # Get the first active Pokémon
        next unless active_pokemon.present?

        moves = active_pokemon[:moves].reject { |move| move[:disabled] } # Filter out disabled moves

        random_move = moves.sample # Select a random move
        random_move_name = random_move[:move] # Return the move name
        user = Faker::Internet.username

        move_requests = [
          "let's go with #{random_move_name}!",
          "how about #{random_move_name}?",
          "use #{random_move_name} now!",
          "I suggest #{random_move_name}.",
          "pick #{random_move_name}!",
          "I think we should use #{random_move_name}.",
          "let's try #{random_move_name}.",
          "go for #{random_move_name}!",
          "choose #{random_move_name}!",
          "let's hit with #{random_move_name}!"
        ]
        audio_mode_puts 'new chat message'
        chat_messages << "#{user}: #{move_requests.sample}"
      end

      # EM.add_periodic_timer(10) do
      #   openai_ws.send({
      #     "type": 'conversation.item.create',
      #     "item": {
      #       "type": 'message',
      #       "role": 'user',
      #       "content": [
      #         {
      #           "type": 'input_text',
      #           "text": 'Right now you have a blastoise on the field that knows hydro pump and ice beam. your opponent is a jolteon.'
      #         }
      #       ]
      #     }
      #   }.to_json)

      #   openai_ws.send({
      #     "type": 'conversation.item.create',
      #     "item": {
      #       "type": 'message',
      #       "role": 'user',
      #       "content": [
      #         {
      #           "type": 'input_text',
      #           "text": 'beebo8362: use ice beam!!!'
      #         }
      #       ]
      #     }
      #   }.to_json)

      #   openai_ws.send({
      #     "type": 'response.create'
      #   }.to_json)
      # end

      pokemon_showdown_ws.on :open do |event|
        audio_mode_puts 'Connected to Pokemon Showdown WebSocket'
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
            audio_mode_puts "Logged in as #{ENV['POKE_USER']}"
          else
            audio_mode_puts 'Login failed'
          end
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
            audio_mode_puts battle_id
            battle_state[:state] = parsed_request.deep_symbolize_keys!
            battle_state[:battle_id] = battle_id
            openai_ws.send({
              "type": 'conversation.item.create',
              "item": {
                "type": 'message',
                "role": 'user',
                "content": [
                  {
                    "type": 'input_text',
                    "text": parsed_request.to_json
                  }
                ]
              }
            }.to_json)
          rescue JSON::ParserError
            # TODO(adenta) this is an expected empty response, dont want to log
          end
        end

        # |inactive|Time left: 150 sec this turn | 150 sec total
        if message.include?('|inactive|') && message.include?('60 sec')
          pokemon_showdown_ws.send("#{battle_state[:battle_id]}|/choose default")
        end
      end

      pokemon_showdown_ws.on :error do |event|
        audio_mode_puts "WebSocket Error: #{event.message}"
      end

      pokemon_showdown_ws.on :close do |event|
        audio_mode_puts "Connection closed: #{event.code} - #{event.reason}"
      end
    end
  end

  task vibe_with_audio: :environment do
    command = 'AUDIO_MODE=true rails realtime:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1  -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'
    system(command)
  end
end
