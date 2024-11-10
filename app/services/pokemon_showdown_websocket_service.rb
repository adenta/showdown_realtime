# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class PokemonShowdownWebsocketService
  URL = 'wss://sim3.psim.us/showdown/websocket'
  AUTH_CHALLANGE_MESSAGE_IDENTIFIER = '|challstr|'
  BATTLE_STATE_MESSAGE_IDENTIFIER = '|request|'
  INACTIVE_MESSAGE_IDENTIFIER = '|inactive|'
  ERROR_MESSAGE_IDENTIFIER = '|error|'
  BAD_CHOICE_IDENTIFIER = '[Invalid choice]'

  def initialize(inbound_message_queue, outbound_message_queue, commentary_message_queue)
    @battle_state = {}
    @endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
    @inbound_message_queue = inbound_message_queue
    @outbound_message_queue = outbound_message_queue
    @commentary_message_queue = commentary_message_queue
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'PKMN'

    showdown_commands_logger = Rails.root.join('log', 'showdown_commands_archive.log')
    @showdown_commands_logger = Logger.new(showdown_commands_logger)
    @showdown_commands_logger.progname = 'SHOD'
  end

  def open_connection(fake_messages = false)
    Async do |task|
      task.async do |subtask|
        Async::WebSocket::Client.connect(@endpoint) do |connection|
          while (message_object = connection.read)
            message = message_object.buffer

            if message.include?('p1a')
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
            end

            send_auth_message(connection, message) if message.include?(AUTH_CHALLANGE_MESSAGE_IDENTIFIER)
            battle_state_handler(connection, message) if message.include?(BATTLE_STATE_MESSAGE_IDENTIFIER)

          end
        end
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
      auth_message = Protocol::WebSocket::TextMessage.new("|/trn #{ENV['POKE_USER']},0,#{assertion}")
      auth_message.send(connection)
      connection.flush
      @logger.info "Logged in as #{ENV['POKE_USER']}"
    else
      @logger.info 'Login failed'
    end
  end

  def battle_state_handler(_connection, message)
    # Extract the JSON part after the '|request|' message
    request_index = message.index('|request|')

    request_json = message[request_index + 9..] # Extract everything after '|request|'
    request_json.strip

    # TODO(adenta) worried this 'next' call might cause problems
    # next unless request_json

    parsed_request = JSON.parse(request_json)
    battle_id = message.split('|').first.split('>').last.chomp.strip

    @battle_state[:state] = parsed_request.deep_symbolize_keys!
    @battle_state[:battle_id] = battle_id

    @commentary_message_queue.enqueue({ type: 'battle_state',
                                        data: BattleFormatter.format_battle(@battle_state[:state]),
                                        created_at: Time.zone.now })
    @outbound_message_queue.enqueue({
      "type": 'response.cancel'

    }.to_json)

    @outbound_message_queue.enqueue({
      "type": 'response.create',
      "response": {
        'modalities': %w[text audio]
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

    @commentary_message_queue.enqueue({ type: 'inactive_timer',
                                        data: message,
                                        created_at: Time.zone.now })

    match = message.match(/\d+ sec/)
    return if match.blank? || @battle_state.empty?

    time_remaining = match[0].split(' sec').first.to_i
    return if time_remaining > 91

    @logger.info "Not sending a message even though time remaining is #{time_remaining}"

    return

    inactive_message = Protocol::WebSocket::TextMessage.new("#{@battle_state[:battle_id]}|/choose default")
    inactive_message.send(connection)
    connection.flush
  end

  def win_or_tie_handler(connection, message)
    inactive_message = Protocol::WebSocket::TextMessage.new('|/search gen9randombattle')
    inactive_message.send(connection)
    connection.flush

    @commentary_message_queue.enqueue({ type: 'win_or_tie',
                                        data: message,
                                        created_at: Time.zone.now })
  end
end
