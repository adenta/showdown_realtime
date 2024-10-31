require 'faye/websocket'
require 'json'
require 'base64'
require 'net/http'
require 'uri'
require 'clerk'
require 'socket'
require_relative '../audio_mode_helper'
require 'osc-ruby'

module TwitchConnection
  attr_accessor :access_token, :nickname, :channel, :socket

  def initialize(access_token, nickname, channel, openai_ws)
    @access_token = access_token
    @nickname = nickname
    @channel = channel
    @socket = nil
    @openai_ws = openai_ws
  end

  def post_init
    # Send credentials
    send_data "PASS oauth:#{@access_token}\r\n"
    send_data "NICK #{@nickname}\r\n"
    send_data "JOIN #{@channel}\r\n"
  end

  def receive_data(data)
    data.each_line do |line|
      sent_by, body = line.strip.split('#').last&.split(' :')

      if sent_by && body && line.include?('PRIVMSG')
        audio_mode_puts sent_by
        audio_mode_puts body

        @openai_ws.send({
          "type": 'conversation.item.create',
          "item": {
            "type": 'message',
            "role": 'user',
            "content": [
              {
                "type": 'input_text',
                "text": "#{sent_by}: #{body}"
              }
            ]
          }
        }.to_json)

      else
        audio_mode_puts 'no body or sent by found'
      end

      # Respond to PING to stay connected
      send_data 'PONG :tmi.twitch.tv\r\n' if line.start_with?('PING')
    end
  rescue StandardError => e
    audio_mode_puts "Error: #{e.message}"
    audio_mode_puts e.backtrace.join("\n")
  end

  def unbind
    EM.stop
  end
end

namespace :realtime do
  include AudioModeHelper

  task vibe: :environment do
    battle_state = {}
    talking_at = nil
    client = OSC::Client.new('localhost', 39_540)

    clerk = Clerk::SDK.new(api_key: ENV['CLERK_SECRET_KEY'])

    # Fetch OAuth token for Twitch
    access_token = clerk.users.oauth_access_token(ENV['CLERK_USER_ID'], 'twitch').first['token']
    nickname = 'adetna'
    channel = '#adetna'
    server = 'irc.chat.twitch.tv'
    port = 6667

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

      EM.connect(server, port, TwitchConnection, access_token, nickname, channel, openai_ws)

      EM.defer do
        loop do
          input = gets.chomp
          audio_mode_puts "Received: #{input}"
          openai_ws.send({
            "type": 'conversation.item.create',
            "item": {
              "type": 'message',
              "role": 'user',
              "content": [
                {
                  "type": 'input_text',
                  "text": input
                }
              ]
            }
          }.to_json)
        end
      end

      openai_ws.on :open do |event|
        audio_mode_puts 'Connected to OpenAI WebSocket'
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
                "description": 'switches to an active pokemon. Only choose a pokemon when someone.',
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
            "tool_choice": 'auto',
            "temperature": 1
          }
        }.to_json)
      end

      openai_ws.on :message do |event|
        response = JSON.parse(event.data)

        if response['type'].include? 'response.done'
          audio_mode_puts "Response: #{response.dig('response', 'output', 0, 'content', 0, 'transcript')}"
        end

        audio_mode_puts response if response['type'].include? 'response.function_call_arguments.done'

        if (response['type'].include? 'response.function_call_arguments.done') && response['name'] == 'choose_move'
          next if battle_state.empty?

          args = response['arguments']
          json_args = JSON.parse(args)

          move_name = json_args['move_name']
          active_pokemon = battle_state[:state][:active]
          first_active_pokemon = active_pokemon&.first

          next unless first_active_pokemon.present?

          first_active_pokemon[:moves].each_with_index do |move, i|
            pokemon_showdown_ws.send("#{battle_state[:battle_id]}|/move #{i + 1}") if move[:move] == move_name
          end
        end

        if (response['type'].include? 'response.function_call_arguments.done') && response['name'] == 'switch_pokemon'
          args = response['arguments']
          json_args = JSON.parse(args)

          switch_name = json_args['switch_name']

          pokemon = battle_state.dig(:side, :pokemon)
          next unless pokemon.present?

          pokemon.each_with_index do |pokemon, i|
            if pokemon[:ident].include?(switch_name)
              pokemon_showdown_ws.send("#{battle_state[:battle_id]}|/switch #{i + 1}")
            end
          end
        end

        if response['type'] == 'response.audio.delta' && response['delta']
          begin
            # Base64 encoced PCM packets
            audio_payload = response['delta']

            talking_at = Time.zone.now
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

      EM.add_periodic_timer(0.1) do
        if rand > 0.98
          client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'eyeBlinkLeft', 1.to_f))
          client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'eyeBlinkRight', 1.to_f))
          sleep 0.15
          client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'eyeBlinkLeft', 0.to_f))
          client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'eyeBlinkRight', 0.to_f))
        end

        if rand > 0.5
          client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'psHeadLeftRight', [-0.01, 0.0, 0.01].sample))
          client.send(OSC::Message.new('/VMC/Ext/Blend/Val', 'psHeadRoll', [-0.01, 0.0, 0.01].sample))
        end

        # if talking_at && (Time.zone.now - talking_at < 0.1.seconds)
        #   variable = 'ftMouthOpen'
        #   value = 0.5

        #   message = OSC::Message.new('/VMC/Ext/Blend/Val', variable, value)
        #   client.send(message)
        # end
      end

      EM.add_periodic_timer(10) do
        audio_mode_puts 'creating a response'
        # openai_ws.send({
        #   "type": 'response.cancel'
        # }.to_json)

        openai_ws.send({
          "type": 'response.create'
        }.to_json)

        pokemon_showdown_ws.send("#{battle_state[:battle_id]}|/timer on")
      end

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
        # |inactive|Time left: 70 sec this turn | 70 sec total
        # |error|[Invalid choice]
        # GAME_OVER_MESSAGE = "|error|[Invalid choice] Can't do anything: The game is over"
        #   TOO_LATE_MESSAGE="|error|[Invalid choice] Sorry, too late to make a different move; the next turn has already started"
        #   NOTHING_TO_CHOOSE = "|error|[Invalid choice] There's nothing to choose"
        if message.include?('|inactive|') || message.include?('|error|') || message.include?('[Invalid choice]')
          openai_ws.send({
            "type": 'conversation.item.create',
            "item": {
              "type": 'message',
              "role": 'user',
              "content": [
                {
                  "type": 'input_text',
                  "text": message
                }
              ]
            }
          }.to_json)

          match = message.match(/\d+ sec/)
          next unless match

          time_remaining = match[0].split(' sec').first.to_i
          pokemon_showdown_ws.send("#{battle_state[:battle_id]}|/choose default") if time_remaining < 91
        end

        pokemon_showdown_ws.send('|/search gen9randombattle') if message.include?('|win|') || message.include?('|tie|')
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

  task stream_in_realtime: :environment do
    # ffplay -fflags nobuffer -flags low_delay -strict experimental -analyzeduration 0 -probesize 32 rtmp://localhost:1935/live/stream
  end

  task move_mouth: :environment do
    client = OSC::Client.new('localhost', 39_540)
    count = 0
    loop do
      # variables = %w[
      #  'psHeadYaw',
      #             'psHeadLeftRight',
      #             'psHeadRoll',
      #             'browDownLeft',
      #             'browDownRight',
      #             'ftEyeXLeft',
      #             'ftEyeYLeft',
      #             'ftEyeXRight',
      #             'ftEyeYRight',
      #             'jawOpen',
      #             'mouthPucker',
      #             'ftMouthEmotion',
      #             'ftMouthOpen',
      #             'ftMouthX',
      #             'tongueOut',
      #             'psLightingRed',
      #             'psLightingGreen',
      #             'psLightingBlue',
      #             'ftA',
      #             'ftHead',
      #             'eyeBlinkLeft',
      #             'eyeBlinkRight',
      #             'eyeSquintLeft',
      #             'eyeSquintRight',
      #             'eyeWideLeft',
      #             'eyeWideRight',
      #             'mouthFunnel',
      #             'mouthLeft',
      #             'mouthRight',
      #             'browOuterUpLeft',
      #             'browOuterUpRight',
      #             'cheekPuff',
      #             'noseSneerLeft',
      #             'noseSneerRight'
      # ]

      variable = 'ftMouthOpen'
      value = count.even? ? 0.01 : 0.5
      count += 1

      puts value
      puts variable

      message = OSC::Message.new('/VMC/Ext/Blend/Val', variable, value)
      client.send(message)
      sleep(0.1)
    end
  end
end
