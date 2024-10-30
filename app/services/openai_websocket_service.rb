# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class OpenaiWebsocketService
  URL = 'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01'
  HEADERS = {
    'Authorization': "Bearer #{ENV.fetch('OPENAI_API_KEY', nil)}",
    'OpenAI-Beta': 'realtime=v1'
  }.freeze

  INSTRUCTIONS = 'You are a helpful assistant'

  SESSION_UPDATE = {
    'type': 'session.update',
    'session': {
      "turn_detection": {
        "type": 'server_vad'
      },
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
    @endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
    @inbound_message_queue = inbound_message_queue
    @outbound_message_queue = outbound_message_queue
  end

  def open_connection
    Async do
      Async::WebSocket::Client.connect(@endpoint, headers: HEADERS) do |connection|
        session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
        session_update_message.send(connection)
        connection.flush

        process_inbound_messages(connection)

        while (message = connection.read)
          response = JSON.parse(message)
          function_call = response['type'].include? 'response.function_call_arguments.done'

          if function_call && response['name'] == 'choose_move'
            choose_move(connection, response)
          elsif function_call && response['name'] == 'switch_pokemon'
            switch_pokemon(connection, response)
          elsif response['type'] == 'response.audio.delta' && response['delta']
            begin
              # Base64 encoced PCM packets
              audio_payload = response['delta']

              raise NotImplementedError

              # if ENV['AUDIO_MODE'] == 'true'
              #   STDOUT.write(Base64.decode64(audio_payload))
              #   STDOUT.flush
              # end
            rescue StandardError => e
              puts "Error processing audio data: #{e}"
            end
          end
        end
      end
    end
  end

  def process_inbound_messages(connection)
    Async do
      loop do
        message = @inbound_message_queue.dequeue

        puts message

        openai_message = Protocol::WebSocket::TextMessage.generate(message)
        openai_message.send(connection)
        connection.flush
      end
    end
  end

  def choose_move(connection, response)
    args = response['arguments']
    json_args = JSON.parse(args)

    move_name = json_args['move_name']
    outbound_message_queue.enqueue({ type: 'choose_move', move_name: move_name })
  end

  def switch_pokemon(connection, response)
    args = response['arguments']
    json_args = JSON.parse(args)

    switch_name = json_args['switch_name']
    outbound_message_queue.enqueue({ type: 'switch_pokemon', switch_name: switch_name })
  end
end
