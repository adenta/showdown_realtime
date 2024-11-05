class OpenaiWebsocketServiceFaye
  URL = 'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01'
  HEADERS = {
    'Authorization': "Bearer #{ENV.fetch('OPENAI_API_KEY', nil)}",
    'OpenAI-Beta': 'realtime=v1'
  }

  INSTRUCTIONS = 'You are a streamer playing a game of pokemon. When someone suggests a move, Chat with the audiance with some commentary about the game you are playing.'

  SESSION_UPDATE = {
    'type': 'session.update',
    'session': {
      # "turn_detection": {
      #   "type": 'server_vad'
      # },
      'input_audio_format': 'g711_ulaw',
      'output_audio_format': 'g711_ulaw',
      'voice': 'alloy',
      'instructions': INSTRUCTIONS,
      'modalities': %w[text audio],
      'temperature': 1,
      "tools": [
        {
          "type": 'function',
          "name": 'choose_move',
          "description": 'chooses a move in a game of pokemon. Only choose a move when someone suggests it.',
          "parameters": {
            "type": 'object',
            "properties": {
              "move_name": {
                "type": 'string',
                "description": 'the name of the move'
              }
            },
            "required": [
              'move_name'
            ]
          }
        },
        {
          "type": 'function',
          "name": 'switch_pokemon',
          "description": 'switches to an active pokemon. Only choose a pokemon when someone suggests it.',
          "parameters": {
            "type": 'object',
            "properties": {
              "switch_name": {
                "type": 'string',
                "description": 'the name of the pokemon to switch to'
              }
            },
            "required": [
              'switch_name'
            ]
          }
        }
      ],
      "tool_choice": 'auto'
    }
  }.freeze

  def initialize(inbound_message_queue, outbound_message_queue)
    @inbound_message_queue = inbound_message_queue
    @outbound_message_queue = outbound_message_queue
    log_filename = Rails.root.join('log', 'demo.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'OPENAI'
  end

  def open_connection
    @logger.info 'Opening connection'
    openai_ws = Faye::WebSocket::Client.new(
      'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01', nil, {
        headers: {
          'Authorization' => "Bearer #{ENV['OPENAI_API_KEY']}",
          'OpenAI-Beta' => 'realtime=v1'
        }
      }
    )
    openai_ws.on :open do |event|
      @logger.info 'Connection opened'
      openai_ws.send(SESSION_UPDATE.to_json)
    end

    EM.defer do
      loop do
        message = @inbound_message_queue.shift
        next unless message.present?

        @logger.info message
        openai_ws.send(message)

        sleep 1
      end
    end

    openai_ws.on :message do |event|
      response = JSON.parse(event.data)

      @logger.info response['type']

      @logger.info response if response['type'] == 'error'

      function_call = response['type'].include? 'response.function_call_arguments.done'

      if function_call && response['name'] == 'choose_move'
        choose_move(response)
      elsif function_call && response['name'] == 'switch_pokemon'
        switch_pokemon(response)
      elsif response['type'] == 'response.audio.delta' && response['delta']
        begin
          # Base64 encoced PCM packets
          audio_payload = response['delta']

          if ENV['SEND_AUDIO_TO_STDOUT'] == 'true'
            STDOUT.write(Base64.decode64(audio_payload))
            STDOUT.flush
          end
        rescue StandardError => e
          @logger.info "Error processing audio data: #{e}"
        end
      end
    end
  end

  def choose_move(response)
    args = response['arguments']
    json_args = JSON.parse(args)

    move_name = json_args['move_name']
    @outbound_message_queue << ({ type: 'choose_move', move_name: move_name })
  end

  def switch_pokemon(response)
    @logger.info 'switching pokemon'
    args = response['arguments']
    json_args = JSON.parse(args)

    switch_name = json_args['switch_name']
    @outbound_message_queue << ({ type: 'switch_pokemon', switch_name: switch_name })
  end
end
