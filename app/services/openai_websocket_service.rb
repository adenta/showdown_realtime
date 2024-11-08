# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class OpenaiWebsocketService
  URL = 'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview'
  HEADERS = {
    'Authorization': "Bearer #{ENV.fetch('OPENAI_API_KEY', nil)}",
    'OpenAI-Beta': 'realtime=v1'
  }.freeze

  INSTRUCTIONS = <<~TXT
    Your name is Chatte, you have 3.2 million subscribers across youtube and twitch. You are a high energy twentysomething streamer playing a game of pokemon showdown.

    When someone suggests a move,chat with the audience with some commentary about the game.

    Always respond with audio and function calls, never text. Keep your responses short and energetic.

    When someone chooses a move or switches pokemon, provide some additional commentary about#{' '}
    the action you are doing, in addition to calling the right function.

    Sometimes, chat might misspell a move or a pokemon name. Be forgiving!

    Becasue you are chatting with a twitch stream, THEY can HEAR you, but you can't hear them. They can only send text messages. You have to speak with audio so chat can here you, and chat will respond with text messages, and text messages only.
  TXT

  SESSION_UPDATE = {
    'type': 'session.update',
    'session': {
      # "turn_detection": {
      #   "type": 'server_vad'
      # },
      'input_audio_format': 'pcm16',
      'output_audio_format': 'pcm16',
      'voice': 'sage',
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
    @endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
    @inbound_message_queue = inbound_message_queue
    @outbound_message_queue = outbound_message_queue
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'OPENAI'
  end

  def open_connection
    Async do |task|
      Async::WebSocket::Client.connect(@endpoint, headers: HEADERS) do |connection|
        @logger.info 'Connection established to OpenAI'
        session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
        session_update_message.send(connection)
        connection.flush

        session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
        session_update_message.send(connection)
        connection.flush

        @inbound_message_queue.enqueue({
          "type": 'conversation.item.create',
          "item": {
            "type": 'message',
            "role": 'user',
            "content": [
              {
                "type": 'input_text',
                "text": 'How are you?'
              }
            ]
          }
        }.to_json)

        @inbound_message_queue.enqueue({
          "type": 'response.create',
          "response": {
            'modalities': %w[text audio]
          }
        }.to_json)

        inbound_message_task = process_inbound_messages(connection)

        message_reader_task = task.async do |subtask|
          @logger.info 'Reading Messages from OpenAI'

          while (message = connection.read)
            response = JSON.parse(message)

            @logger.info response['type']

            @logger.info response if response['type'] == 'error' || response['type'] == 'rate_limits.updated'

            function_call = response['type'].include? 'response.function_call_arguments.done'

            if function_call && response['name'] == 'choose_move'
              choose_move(connection, response)
            elsif function_call && response['name'] == 'switch_pokemon'
              switch_pokemon(connection, response)
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

        # Make sure the connection is closed at least two seconds before the next session begins
        task.sleep(ENV['SESSION_DURATION_IN_MINUTES'].to_i.minutes - 2.seconds)

        @logger.info 'Connection closed with OpenAI'

        inbound_message_task.stop
        message_reader_task.stop
        connection.close
      end
    end
  end

  def process_inbound_messages(connection)
    @logger.info 'Processing inbound messages'
    Async do
      loop do
        message = @inbound_message_queue.dequeue

        openai_message = Protocol::WebSocket::TextMessage.generate(JSON.parse(message))
        openai_message.send(connection)
        connection.flush
      end
    end
  end

  def choose_move(connection, response)
    args = response['arguments']
    json_args = JSON.parse(args)

    move_name = json_args['move_name']
    @outbound_message_queue.enqueue({ type: 'choose_move', move_name: move_name })
  end

  def switch_pokemon(connection, response)
    @logger.info 'switching pokemon'
    args = response['arguments']
    json_args = JSON.parse(args)

    switch_name = json_args['switch_name']
    @outbound_message_queue.enqueue({ type: 'switch_pokemon', switch_name: switch_name })
  end
end
