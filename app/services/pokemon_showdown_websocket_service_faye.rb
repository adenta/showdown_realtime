class PokemonShowdownWebsocketServiceFaye
  URL = 'wss://sim3.psim.us/showdown/websocket'
  AUTH_CHALLANGE_MESSAGE_IDENTIFIER = '|challstr|'
  BATTLE_STATE_MESSAGE_IDENTIFIER = '|request|'
  INACTIVE_MESSAGE_IDENTIFIER = '|inactive|'
  ERROR_MESSAGE_IDENTIFIER = '|error|'
  BAD_CHOICE_IDENTIFIER = '[Invalid choice]'

  def initialize(inbound_message_queue, outbound_message_queue)
    @battle_state = {}
    @inbound_message_queue = inbound_message_queue
    @outbound_message_queue = outbound_message_queue
    log_filename = Rails.root.join('log', 'demo.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'PKMN'
  end

  def open_connection
    pokemon_showdown_ws = Faye::WebSocket::Client.new(
      'wss://sim3.psim.us/showdown/websocket'
    )

    EM.defer do
      loop do
        sleep 1
        message = @inbound_message_queue.shift

        next unless message.present?

        message_type = message[:type]

        case message_type
        when 'choose_move'
          next if @battle_state.empty?

          active_pokemon = @battle_state[:state][:active]
          first_active_pokemon = active_pokemon&.first

          next unless first_active_pokemon.present?

          first_active_pokemon[:moves].each_with_index do |move, i|
            next unless move[:move] == message[:move_name]

            command = "#{@battle_state[:battle_id]}|/move #{i + 1}"
            choose_move_message = Protocol::WebSocket::TextMessage.new(command)
            choose_move_message.send(connection)
            connection.flush
          end
        when 'switch_pokemon'
          next if @battle_state.empty?

          # pokemon is both singular and plural
          pokemans = @battle_state.dig(:state, :side, :pokemon)
          next unless pokemans.present?

          pokemans.each_with_index do |pokemon, i|
            next unless pokemon[:ident].include?(message[:switch_name])

            switch_pokemon_message = Protocol::WebSocket::TextMessage.new("#{@battle_state[:battle_id]}|/switch #{i + 1}")
            switch_pokemon_message.send(connection)
            connection.flush
          end

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

    pokemon_showdown_ws.on :message do |event|
      message = event.data

      send_auth_message(pokemon_showdown_ws, message) if message.include?(AUTH_CHALLANGE_MESSAGE_IDENTIFIER)
      battle_state_handler(pokemon_showdown_ws, message) if message.include?(BATTLE_STATE_MESSAGE_IDENTIFIER)

      # inactive_message = message.include?(INACTIVE_MESSAGE_IDENTIFIER)
      # error_message = message.include?(ERROR_MESSAGE_IDENTIFIER)
      # invalid_choice_message = message.include?('[Invalid choice]')
      # invoke_inactive_message_handler = inactive_message || error_message || invalid_choice_message
      # inactive_message_handler(pokemon_showdown_ws, message) if invoke_inactive_message_handler

      win_or_tie_handler(pokemon_showdown_ws, message) if message.include?('|win|') || message.include?('|tie|')
    end
  end

  def send_auth_message(pokemon_showdown_ws, message)
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
      @logger.info "Logged in as #{ENV['POKE_USER']}"
    else
      @logger.info 'Login failed'
    end
  end

  def battle_state_handler(_pokemon_showdown_ws, message)
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
    @outbound_message_queue << ({
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

  # def inactive_message_handler(pokemon_showdown_ws, message)
  #   @outbound_message_queue << ({
  #     "type": 'conversation.item.create',
  #     "item": {
  #       "type": 'message',
  #       "role": 'user',
  #       "content": [
  #         {
  #           "type": 'input_text',
  #           "text": message
  #         }
  #       ]
  #     }
  #   }.to_json)

  #   match = message.match(/\d+ sec/)
  #   return if match.blank? || @battle_state.empty?

  #   time_remaining = match[0].split(' sec').first.to_i
  #   return if time_remaining > 91

  #   @logger.info "Not sending a message even though time remaining is #{time_remaining}"

  #   nil
  # end

  def win_or_tie_handler(pokemon_showdown_ws, _message)
    pokemon_showdown_ws.send('|/search gen9randombattle')
  end
end
