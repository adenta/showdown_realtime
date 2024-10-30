# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class PokemonShowdownWebsocketService
  URL = 'wss://sim3.psim.us/showdown/websocket'

  def initialize(inbound_message_queue, outbound_message_queue)
    @battle_state = {}
    @endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
    @inbound_message_queue = inbound_message_queue
    @outbound_message_queue = outbound_message_queue
  end

  def open_connection
    Async do
      Async::WebSocket::Client.connect(@endpoint) do |connection|
        process_inbound_messages(connection)

        while message_object = connection.read
          message = message_object.buffer

          send_auth_message(connection, message) if message.include?('|challstr|')
          battle_state_handler(connection, message) if message.include?('|request|')
          if message.include?('|inactive|') || message.include?('|error|') || message.include?('[Invalid choice]')
            inactive_message_handler(connection,
                                     message)
          end

          win_or_tie_handler(connection, message) if message.include?('|win|') || message.include?('|tie|')

        end
      end
    end
  end

  def process_inbound_messages(connection)
    Async do
      loop do
        message = @inbound_message_queue.dequeue

        raise NotImplementedError
      end
    end
  end

  def send_auth_message(connection, message)
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
      auth_message = Protocol::WebSocket::TextMessage.generate("|/trn #{ENV['POKE_USER']},0,#{assertion}")
      auth_message.send(connection)
      connection.flush
      puts "Logged in as #{ENV['POKE_USER']}"
    else
      puts 'Login failed'
    end
  end

  def battle_state_handler(connection, message)
    # Extract the JSON part after the '|request|' message
    request_index = message.index('|request|')

    request_json = message[request_index + 9..-1] # Extract everything after '|request|'
    request_json.strip

    # TODO(adenta) worried this 'next' call might cause problems
    # next unless request_json

    parsed_request = JSON.parse(request_json)
    battle_id = message.split('|').first.split('>').last.chomp.strip
    @battle_state[:state] = parsed_request.deep_symbolize_keys!
    @battle_state[:battle_id] = battle_id
    @outbound_message_queue.enqueue({
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

  def inactive_message_handler(connection, message)
    @outbound_message_queue.enqueue({
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
    return unless match

    time_remaining = match[0].split(' sec').first.to_i
    return if time_remaining < 91

    inactive_message = Protocol::WebSocket::TextMessage.generate("#{@battle_state[:battle_id]}|/choose default")
    inactive_message.send(connection)
    connection.flush
  end

  def win_or_tie_handler(connection, message)
    inactive_message = Protocol::WebSocket::TextMessage.generate('|/search gen9randombattle')
    inactive_message.send(connection)
    connection.flush
  end
end
