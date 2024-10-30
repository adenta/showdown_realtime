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
    Async::WebSocket::Client.connect(@endpoint) do |connection|
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
    end

    # Async do |task|
    #   task.sleep 5
    #   scene_name = GAMEPLAY_SCENE
    #   code = 2
    #   loop do
    #     scene_payload = {
    #       'op' => code,
    #       'd' => {
    #         'requestType' => 'SetCurrentProgramScene',
    #         'requestId' => rand(1..1000).to_s,
    #         'requestData' => { 'sceneName' => scene_name }
    #       }
    #     }

    #     code += 1

    #     scene_message = Protocol::WebSocket::TextMessage.generate(scene_payload)
    #     scene_message.send(connection)
    #     connection.flush

    #     scene_name = scene_name == GAMEPLAY_SCENE ? PAUSE_SCENE : GAMEPLAY_SCENE
    #   rescue StandardError => e
    #     puts e
    #   end
    # end
    # end
  end
end

# # OBS WebSocket server details from ENV variables
# OBS_SERVER_ADDRESS = ENV['OBS_SERVER_ADDRESS']
# OBS_SERVER_PASSWORD = ENV['OBS_SERVER_PASSWORD']

# # Function to authenticate with the OBS server
# def authenticate(ws)
#   auth_payload = {
#     'op' => 1,
#     'd' => {
#       'rpcVersion' => 1,
#       'authentication' => OBS_SERVER_PASSWORD
#     }
#   }
#   ws.send_text(auth_payload.to_json)
# end

# # Function to switch scenes
# def switch_scene(ws, scene_name)
#   payload = {
#     'op' => 6,
#     'd' => {
#       'requestType' => 'SetCurrentProgramScene',
#       'requestId' => rand(1..1000).to_s,
#       'requestData' => { 'sceneName' => scene_name }
#     }
#   }
#   ws.send_text(payload.to_json)
# end

# Async do
#   Async::WebSocket::Client.connect(OBS_SERVER_ADDRESS) do |ws|
#     authenticate(ws)

#     current_scene = 'gameplay'

#     loop do
#       switch_scene(ws, current_scene)
#       current_scene = current_scene == 'gameplay' ? 'pause' : 'gameplay'
#       sleep 5 # Adjust delay as needed for toggling
#     end
#   end
# end
