require 'faye/websocket'
require 'json'
require 'base64'
require 'net/http'
require 'uri'
require 'clerk'
require 'socket'
require_relative '../audio_mode_helper'
require 'osc-ruby'

INSTRUCTIONS = 'You are a streamer playing a game of pokemon. When someone suggests a move, Chat with the audiance with some commentary about the game you are playing.'

SESSION_UPDATE = {
  'type': 'session.update',
  'session': {
    # "turn_detection": {
    #   "type": 'server_vad'
    # },
    'input_audio_format': 'g711_ulaw',
    'output_audio_format': 'g711_ulaw',
    'voice': 'coral',
    'instructions': INSTRUCTIONS,
    'modalities': %w[text audio],
    'temperature': 1,
    "tools": [
      {
        "type": 'function',
        "name": 'choose_move',
        "description": 'chooses a move in a game of pokemon. Only choose a move when someone suggests it.',
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
      },
      {
        "type": 'function',
        "name": 'switch_pokemon',
        "description": 'switches to an active pokemon. Only choose a pokemon when someone suggests it.',
        "parameters": {
          "type": 'object',
          "properties": {
            "switch_name": {
              "type": 'string',
              "description": 'the name of the pokemon to switch to'
            }
          },
          "required": [
            'switch_name'
          ]
        }
      }
    ],
    "tool_choice": 'auto'
  }
}.freeze

namespace :demo do
  task vibe: :environment do
    battle_state = {}
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'DEMO'
    file_path = Rails.root.join('log', 'commands.log')
    file = File.open(file_path, 'r')
    file.seek(0, IO::SEEK_END) # Move to the end of the file

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
        @logger.info 'Connection opened'
        openai_ws.send(SESSION_UPDATE.to_json)
      end

      openai_ws.on :message do |event|
        response = JSON.parse(event.data)

        @logger.info response['type']

        @logger.info response if response['type'] == 'error'

        function_call = response['type'].include? 'response.function_call_arguments.done'

        if function_call && response['name'] == 'choose_move'
          raise NotImplementedError
          choose_move(response)
        elsif function_call && response['name'] == 'switch_pokemon'
          raise NotImplementedError
          switch_pokemon(response)
        elsif response['type'] == 'response.audio.delta' && response['delta']
          begin
            # Base64 encoced PCM packets
            audio_payload = response['delta']

            if ENV['SEND_AUDIO_TO_STDOUT'] == 'true'
              STDOUT.write(Base64.decode64(audio_payload))
              STDOUT.flush
            end
          rescue StandardError => e
            @logger.info "Error processing audio data: #{e}"
          end
        end
      end

      EM.defer do
        loop do
          line = file.gets
          if line
            openai_ws.send({
              "type": 'conversation.item.create',
              "item": {
                "type": 'message',
                "role": 'user',
                "content": [
                  {
                    "type": 'input_text',
                    "text": "chairlaw: #{line.strip}"
                  }
                ]
              }
            }.to_json)
            openai_ws.send({
              "type": 'response.create'
            }.to_json)
          else
            sleep 1 # Sleep for a second if no new line is found
          end
        end
      end
    end
  end

  task vibe_over_stdout: :environment do
    command = 'SEND_AUDIO_TO_STDOUT=true rails demo:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1  -strict experimental -analyzeduration 0 -probesize 32 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'
    system(command)
  end

  task send_commands: :environment do
    Async do |task|
      file_path = Rails.root.join('log', 'commands.log')
      File.open(file_path, 'a') do |file|
        loop do
          puts "Enter a message to log (or type 'exit' to quit):"
          input = STDIN.gets.strip
          break if input.downcase == 'exit'

          file.puts input
          file.flush
        end
      end
    end
  end
end
