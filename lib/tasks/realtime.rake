require 'faye/websocket'
require 'json'
require 'base64'
require 'net/http'
require 'uri'

namespace :realtime do
  task vibe: :environment do
    battle_state = {}
    EM.run do
      openai_ws = Faye::WebSocket::Client.new(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01', nil, {
          headers: {
            'Authorization' => "Bearer #{ENV['OPENAI_API_KEY']}",
            'OpenAI-Beta' => 'realtime=v1'
          }
        }
      )

      openai_ws.on :open do |event|
        puts 'Connected to OpenAI WebSocket'
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
        # puts "Received message: #{response}"
      end

      openai_ws.on :error do |event|
        puts "WebSocket Error: #{event.message}"
      end

      openai_ws.on :close do |event|
        puts "Connection closed: #{event.code} - #{event.reason}"
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

      pokemon_showdown_ws = Faye::WebSocket::Client.new(
        'wss://sim3.psim.us/showdown/websocket'
      )

      pokemon_showdown_ws.on :open do |event|
        puts 'Connected to Pokemon Showdown WebSocket'
      end

      pokemon_showdown_ws.on :message do |event|
        message = event.data
        next unless message.include?('|challstr|')

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
        else
          puts 'Login failed'
        end
      end

      pokemon_showdown_ws.on :error do |event|
        puts "WebSocket Error: #{event.message}"
      end

      pokemon_showdown_ws.on :close do |event|
        puts "Connection closed: #{event.code} - #{event.reason}"
      end
    end
  end
end
