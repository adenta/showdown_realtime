require 'faye/websocket'
require 'json'
require 'base64'

namespace :realtime do
  task vibe: :environment do
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
        puts "Received message: #{response}"
      end

      openai_ws.on :error do |event|
        puts "WebSocket Error: #{event.message}"
      end

      openai_ws.on :close do |event|
        puts "Connection closed: #{event.code} - #{event.reason}"
      end
    end
  end
end
