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
  end

  def open_connection(fake_messages = false)
    Async do |task|
      task.async do |subtask|
        Async::WebSocket::Client.connect(@endpoint) do |connection|
          process_inbound_messages(connection)

          while (message_object = connection.read)
            message = message_object.buffer

            send_auth_message(connection, message) if message.include?(AUTH_CHALLANGE_MESSAGE_IDENTIFIER)
            battle_state_handler(connection, message) if message.include?(BATTLE_STATE_MESSAGE_IDENTIFIER)

            inactive_message = message.include?(INACTIVE_MESSAGE_IDENTIFIER)
            error_message = message.include?(ERROR_MESSAGE_IDENTIFIER)
            invalid_choice_message = message.include?('[Invalid choice]')
            invoke_inactive_message_handler = inactive_message || error_message || invalid_choice_message

            inactive_message_handler(connection, message) if invoke_inactive_message_handler

            win_or_tie_handler(connection, message) if message.include?('|win|') || message.include?('|tie|')

          end
        end
      end

      return unless fake_messages

      task.sleep 10

      # this is happening here because we have access to the battle state
      loop do
        messages = FakeChatService.generate_messages(@battle_state)

        messages['chat_messages'].each do |message|
          task.sleep(rand(0.2..0.8))

          @outbound_message_queue.enqueue({
            "type": 'conversation.item.create',
            "item": {
              "type": 'message',
              "role": 'user',
              "content": [
                {
                  "type": 'input_text',
                  "text": "#{message['username']}: #{message['body']}"
                }
              ]
            }
          }.to_json)
        end

        @outbound_message_queue.enqueue({
          "type": 'conversation.item.create',
          "item": {
            "type": 'message',
            "role": 'user',
            "content": [
              {
                "type": 'input_text',
                "text": 'Based on the messages from chat, what should we do?'
              }
            ]
          }
        }.to_json)

        @outbound_message_queue.enqueue({
          "type": 'response.create',
          "response": {
            'modalities': %w[text audio]
          }
        }.to_json)
      end
    end
  end

  def process_inbound_messages(connection)
    Async do
      loop do
        message = @inbound_message_queue.dequeue

        message_type = message[:type]

        case message_type
        when 'choose_move'
          next if @battle_state.empty?

          active_pokemon = @battle_state[:state][:active]
          first_active_pokemon = active_pokemon&.first

          next unless first_active_pokemon.present?

          found_move = false

          first_active_pokemon[:moves].each_with_index do |move, i|
            next unless move[:move] == message[:move_name]

            found_move = true

            command = "#{@battle_state[:battle_id]}|/move #{i + 1}"
            choose_move_message = Protocol::WebSocket::TextMessage.new(command)
            choose_move_message.send(connection)
            connection.flush
          end

          @logger.info "Could not find a move with the name #{message[:move_name]}" unless found_move

        when 'switch_pokemon'
          next if @battle_state.empty?

          # pokemon is both singular and plural
          pokemans = @battle_state.dig(:state, :side, :pokemon)
          next unless pokemans.present?

          found_pokemon = false

          pokemans.each_with_index do |pokemon, i|
            next unless pokemon[:ident].include?(message[:switch_name])

            found_pokemon = true

            command = "#{@battle_state[:battle_id]}|/switch #{i + 1}"
            switch_pokemon_message = Protocol::WebSocket::TextMessage.new(command)
            switch_pokemon_message.send(connection)
            connection.flush
          end

          @logger.info "Could not find a pokemon with the name #{message[:switch_name]}" unless found_pokemon

        when 'default'

          command = "#{@battle_state[:battle_id]}|/choose default"
          inactive_message = Protocol::WebSocket::TextMessage.new(command)
          inactive_message.send(connection)
          connection.flush
        else
          raise NotImplementedError
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
    return if match.blank? || @battle_state.empty?

    time_remaining = match[0].split(' sec').first.to_i
    return if time_remaining > 91

    @logger.info "Not sending a message even though time remaining is #{time_remaining}"

    return

    inactive_message = Protocol::WebSocket::TextMessage.new("#{@battle_state[:battle_id]}|/choose default")
    inactive_message.send(connection)
    connection.flush
  end

  def win_or_tie_handler(connection, _message)
    inactive_message = Protocol::WebSocket::TextMessage.new('|/search gen9randombattle')
    inactive_message.send(connection)
    connection.flush
  end
end
