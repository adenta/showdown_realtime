require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'openssl'
require 'base64'

namespace :obs_faye do
  task authenticate: :environment do
    url = ENV['OBS_WEBSOCKET_URL']
    password = ENV['OBS_WEBSOCKET_PASSWORD']

    EM.run do
      # headers = { 'Sec-WebSocket-Protocol' => 'obswebsocket.json' }
      ws = Faye::WebSocket::Client.new(url, nil)

      ws.on :open do |event|
        puts 'Connected to server'
      end

      ws.on :message do |event|
        msg = JSON.parse(event.data)
        op = msg['op']
        data = msg['d']

        case op
        when 0 # Hello
          # Get rpcVersion
          rpc_version = data['rpcVersion']
          authentication = data['authentication']
          if authentication
            challenge = authentication['challenge']
            salt = authentication['salt']
            # Create authentication string
            sha256 = OpenSSL::Digest.new('SHA256')
            password_salt = password + salt
            hash1 = sha256.digest(password_salt)
            base64_secret = Base64.strict_encode64(hash1)
            secret_challenge = base64_secret + challenge
            hash2 = sha256.digest(secret_challenge)
            authentication_string = Base64.strict_encode64(hash2)
          else
            authentication_string = nil
          end

          # Now send Identify message (OpCode 1)
          identify_msg = {
            'op' => 1,
            'd' => {
              'rpcVersion' => rpc_version
            }
          }
          identify_msg['d']['authentication'] = authentication_string if authentication_string
          ws.send(identify_msg.to_json)
        when 2  # Identified
          puts 'Identified with server'
        when 5  # Event
          event_type = data['eventType']
          event_data = data['eventData']
          puts "Event received: #{event_type}"
          puts "Event data: #{event_data}"
        else
          # Print other messages
          puts "Received message: #{msg}"
        end
      end

      ws.on :close do |event|
        puts "Connection closed: code=#{event.code}, reason=#{event.reason}"
        EM.stop
      end

      ws.on :error do |event|
        puts "Error: #{event.message}"
      end
    end
  end
end
