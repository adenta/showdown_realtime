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
      "tools": [],
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
          payload = JSON.parse(message)
          puts payload

          next unless payload['type'] == 'response.audio.delta' && payload['delta']

          enqueue_audio_delta_message
        end
      end
    end
  end

  def process_inbound_messages(connection)
    Async do
      loop do
        message = @inbound_message_queue.dequeue

        raise NotImplementedError

        openai_message = Protocol::WebSocket::TextMessage.generate(message)
        openai_message.send(connection)
        connection.flush
      end
    end
  end

  def enqueue_audio_delta_message
    raise NotImplementedError
    # do something here with @outbound_message_queue
  end
end
