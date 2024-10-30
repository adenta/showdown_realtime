require 'async'
require 'async/http'
require 'async/websocket'

class ObsWebsocketService
  URL = ENV['OBS_WEBSOCKET_URL']

  GAMEPLAY_SCENE = 'gameplay'
  PAUSE_SCENE = 'pause'

  def initialize
    @endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
  end

  def open_connection
    Async::WebSocket::Client.connect(@endpoint) do |connection|
      auth_payload = {
        'op' => 1,
        'd' => {
          'rpcVersion' => 1,
          'authentication' => ENV['OBS_SERVER_PASSWORD']
        }
      }
      auth_message = Protocol::WebSocket::TextMessage.generate(auth_payload)
      auth_message.send(connection)
      connection.flush

      Async do |task|
        while message = connection.read
          puts message.to_h
        end
      end

      Async do |task|
        scene_name = GAMEPLAY_SCENE
        loop do
          scene_payload = {
            'op' => 6,
            'd' => {
              'requestType' => 'SetCurrentProgramScene',
              'requestId' => rand(1..1000).to_s,
              'requestData' => { 'sceneName' => scene_name }
            }
          }

          p
          scene_message = Protocol::WebSocket::TextMessage.generate(scene_payload)
          scene_message.send(connection)
          connection.flush

          scene_name = scene_name == GAMEPLAY_SCENE ? PAUSE_SCENE : GAMEPLAY_SCENE
          task.sleep 5
        end
      end
    end
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
