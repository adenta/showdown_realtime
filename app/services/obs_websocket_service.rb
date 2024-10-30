require 'async'
require 'async/http'
require 'async/websocket'
require 'openssl'
require 'base64'
require 'json'

class ObsWebsocketService
  URL = ENV['OBS_WEBSOCKET_URL']

  GAMEPLAY_SCENE = 'gameplay'
  PAUSE_SCENE = 'pause'

  def initialize
    @endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
  end

  def open_connection
    Async do |task|
      Async::WebSocket::Client.connect(@endpoint) do |connection|
        task.async do |subtask|
          scene = GAMEPLAY_SCENE
          loop do
            subtask.sleep 2

            scene_payload = {
              "op": 6,
              "d": {
                "requestType": 'SetCurrentProgramScene',
                "requestId": SecureRandom.uuid,
                "requestData": {
                  "sceneName": scene
                }
              }
            }

            scene_message = Protocol::WebSocket::TextMessage.generate(scene_payload)
            scene_message.send(connection)
            connection.flush

            scene = scene == GAMEPLAY_SCENE ? PAUSE_SCENE : GAMEPLAY_SCENE
          end
        end

        challange_message = connection.read.to_h

        challenge = challange_message[:d][:authentication][:challenge]
        salt = challange_message[:d][:authentication][:salt]

        # Create authentication string
        sha256 = OpenSSL::Digest.new('SHA256')
        password_salt = ENV['OBS_WEBSOCKET_PASSWORD'] + salt
        hash1 = sha256.digest(password_salt)
        base64_secret = Base64.strict_encode64(hash1)
        secret_challenge = base64_secret + challenge
        hash2 = sha256.digest(secret_challenge)
        authentication_string = Base64.strict_encode64(hash2)

        auth_payload = {
          'op' => 1,
          'd' => {
            'rpcVersion' => 1,
            'authentication' => authentication_string
          }
        }

        begin
          auth_message = Protocol::WebSocket::TextMessage.generate(auth_payload)
          auth_message.send(connection)
          connection.flush
        rescue StandardError => e
          puts e
        end

        while message = connection.read
          puts message.to_h
        end
      ensure
        task&.stop
      end
    end
  end
end
