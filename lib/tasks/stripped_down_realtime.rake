require 'faye/websocket'
require 'json'
require 'base64'
require 'net/http'
require 'uri'
require 'socket'

namespace :stripped_down_realtime do
  include AudioModeHelper

  task vibe: :environment do
    log_filename = Rails.root.join('log', 'demo.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'CONSOLE'

    EM.run do
      @logger.info 'Starting OpenAI WebSocket connection'
      openai_ws = Faye::WebSocket::Client.new(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01', nil, {
          headers: {
            'Authorization' => "Bearer #{ENV['OPENAI_API_KEY']}",
            'OpenAI-Beta' => 'realtime=v1'
          }
        }
      )

      openai_ws.on :open do |event|
        @logger.info 'Con n ecting to OpenAI WebSocket'
        openai_ws.send({
          "type": 'session.update',
          "session": {
            "modalities": %w[
              text
              audio
            ],
            "instructions": "System settings:\nTool use: enabled.\n\nYou are an online streamer playing pokemon on twitch. \nProvide some commentary of the match as it happens. \n Answer chats questions as they are asked. \n When people join chat, greet them. Pick moves suggested by chat. You are a young women who talks kinda fast and is easily excitable. When you take a members suggestion, call them out and thank them for their suggestion.",
            "voice": 'alloy',
            "input_audio_format": 'pcm16',
            "output_audio_format": 'pcm16',
            "input_audio_transcription": {
              "model": 'whisper-1'
            },
            "turn_detection": nil,
            "tools": [],
            "tool_choice": 'auto',
            "temperature": 1
          }
        }.to_json)
      end

      openai_ws.on :message do |event|
        response = JSON.parse(event.data)

        @logger.info response

        if response['type'] == 'response.audio.delta' && response['delta']
          begin
            # Base64 encoced PCM packets
            audio_payload = response['delta']

            if ENV['AUDIO_MODE'] == 'true'
              STDOUT.write(Base64.decode64(audio_payload))
              STDOUT.flush
            end
          rescue StandardError => e
            @logger.info e
          end
        end
      end

      EM.add_periodic_timer(5) do
        openai_ws.send({
          "type": 'conversation.item.create',
          "item": {
            "type": 'message',
            "role": 'user',
            "content": [
              {
                "type": 'input_text',
                "text": 'whats your favorite pokemon'
              }
            ]
          }
        }.to_json)

        openai_ws.send({
          "type": 'response.create'
        }.to_json)
      end
    end
  end

  task vibe_with_audio: :environment do
    command = 'AUDIO_MODE=true rails stripped_down_realtime:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1  -fflags nobuffer -flags low_delay -strict experimental -analyzeduration 0 -probesize 32 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'
    system(command)
  end
end
