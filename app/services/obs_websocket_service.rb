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
    log_filename = Rails.root.join('log', "demo.log")
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'OBS'
  end

  def open_connection
    @logger.info 'hello'
    Async do |task|
      task.async do
        loop do
          @logger.info Time.zone.now
          task.sleep 1
        end
      end
      Async::WebSocket::Client.connect(@endpoint) do |connection|
        send_auth_message(connection)

        switch_between_scenes(connection)

        while message = connection.read
          @logger.info message.to_h
        end
      ensure
        task&.stop
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      @logger.info "OBS isn't running"
    end
  end

  private

  def send_auth_message(connection)
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
      @logger.info e
    end
  end

  def switch_between_scenes(connection)
    Async do |task|
      scene = GAMEPLAY_SCENE
      loop do
        task.sleep 2

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
  end
end
