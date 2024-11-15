# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class OpenaiFunctionService
  URL = 'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview'
  HEADERS = {
    'Authorization': "Bearer #{ENV.fetch('OPENAI_API_KEY', nil)}",
    'OpenAI-Beta': 'realtime=v1'
  }.freeze

  INSTRUCTIONS = <<~TXT
    You are a Chatte, a female, twentysomething online streamer with 2.5 million subscribers. You take chat suggestions and uses the suggestions to play Pokemon.#{' '}
    Keep each of your responses to twenty words or less. Be sure to keep the energy high and the excitement palpable. Only occasionally list out the moves that can be switched to.
  TXT

  SESSION_UPDATE = {
    'type': 'session.update',
    'session': {
      'instructions': INSTRUCTIONS,
      'modalities': %w[text],
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

  def initialize(queue_manager)
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'OAICM'

    endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
    @connection = Async::WebSocket::Client.connect(endpoint, headers: HEADERS)
    @logger.info 'Connection established to OpenAI -- Command'

    @inbound_message_queue = queue_manager.openai_function
    @outbound_message_queue = queue_manager.pokemon_showdown
    @queue_manager = queue_manager

    session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
    session_update_message.send(@connection)
    @connection.flush

    session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
    session_update_message.send(@connection)
    @connection.flush
  end

  def read_messages_from_openai_task
    Async do
      @logger.info 'Reading Messages from OpenAI -- Command'

      while (message = @connection.read)
        response = JSON.parse(message)

        function_call = response['type'].include? 'response.function_call_arguments.done'

        if function_call && response['name'] == 'choose_move'
          choose_move(response)
        elsif function_call && response['name'] == 'switch_pokemon'
          switch_pokemon(response)
        end
      end
    end
  end

  def read_messages_from_queue_task
    @queue_manager.openai_function.enqueue({
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

    @queue_manager.openai_function.enqueue({
      "type": 'response.create',
      "response": {
        'modalities': %w[text]
      }
    }.to_json)

    Async do
      loop do
        message = @queue_manager.openai_function.dequeue

        openai_message = Protocol::WebSocket::TextMessage.generate(JSON.parse(message))
        openai_message.send(@connection)
        @connection.flush
      end
    end
  end

  def choose_move(response)
    args = response['arguments']
    json_args = JSON.parse(args)

    move_name = json_args['move_name']
    @queue_manager.pokemon_showdown.enqueue({ type: 'choose_move', move_name: move_name })
  end

  def switch_pokemon(response)
    args = response['arguments']
    json_args = JSON.parse(args)

    switch_name = json_args['switch_name']
    @queue_manager.pokemon_showdown.enqueue({ type: 'switch_pokemon', switch_name: switch_name })
  end

  def close_connections
    @connection.close
  end
end
