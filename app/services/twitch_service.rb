# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class TwitchService
  NICKNAME = 'adetna'
  CHANNEL = '#adetna'
  SERVER = 'irc.chat.twitch.tv'
  PORT = 6667

  def initialize(queue_manager)
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'TWITC'

    @logger.info 'Connection established to Twitch Chat'

    @queue_manager = queue_manager
  end

  def chat_task
    Async do |task|
      IO::Endpoint.tcp(SERVER, PORT).connect do |socket|
        socket.write "PASS oauth:#{twitch_access_token}\r\n"
        socket.write "NICK #{NICKNAME}\r\n"
        socket.write "JOIN #{CHANNEL}\r\n"

        while (line = socket.gets)
          @logger.info line

          match_data = line.match(/^:(\w+)!\w+@\w+\.tmi\.twitch\.tv PRIVMSG #\w+ :(.+)$/)
          next unless match_data

          sent_by = match_data[1]
          body = match_data[2]

          message = "#{sent_by}: #{body}"

          @logger.info message

          @queue_manager.openai.enqueue({
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

          @queue_manager.openai_function.enqueue({
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

          @queue_manager.openai_function.enqueue({
            "type": 'response.create'
          }.to_json)

        end
      end
    end
  end

  private

  def twitch_access_token
    clerk = Clerk::SDK.new(api_key: ENV['CLERK_SECRET_KEY'])

    # Fetch OAuth token for Twitch
    clerk.users.oauth_access_token(ENV['CLERK_USER_ID'], 'twitch').first['token']
  end
end
