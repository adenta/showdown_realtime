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
    You are a Chatte, a female, twentysomething online streamer with 2.5 million subscribers. You take chat suggestions and uses the suggestions to play Pokemon.#{' '}
    Keep each of your responses to twenty words or less. Be sure to keep the energy high and the excitement palpable. Only occasionally list out the moves that can be switched to.
  TXT

  SESSION_UPDATE = {
    'type': 'session.update',
    'session': {
      'input_audio_format': 'pcm16',
      'output_audio_format': 'pcm16',
      'voice': 'sage',
      'instructions': INSTRUCTIONS,
      'modalities': %w[text audio],
      'temperature': 1
    }
  }.freeze

  def initialize(queue_manager)
    @endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
    @inbound_message_queue = queue_manager.openai
    @outbound_message_queue = queue_manager.pokemon_showdown
    @audio_queue = queue_manager.audio_out

    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'OPENAI'

    @connection = Async::WebSocket::Client.connect(@endpoint, headers: HEADERS)

    @pipe = IO.popen(
      'ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream', 'wb' # Changed 'w' to 'wb'
    )
  end

  def open_connection
    Async do |task|
      @logger.info 'Connection established to OpenAI'
      session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
      session_update_message.send(@connection)
      @connection.flush

      session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
      session_update_message.send(@connection)
      @connection.flush

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

      inbound_message_task = process_inbound_messages

      audio_out_task = task.async do |subtask|
        loop do
          audio_payload = @audio_queue.dequeue

          decoded_audio = Base64.decode64(audio_payload)
          audio_length_ms = (decoded_audio.length / 2.0 / 24_000) * 1000

          @logger.info "Audio length: #{audio_length_ms}"

          @pipe.write(decoded_audio)
          @pipe.flush

          subtask.sleep(audio_length_ms * 0.8 / 1000)
        end
      end

      message_reader_task = task.async do |subtask|
        @logger.info 'Reading Messages from OpenAI'

        while (message = @connection.read)
          response = JSON.parse(message)

          next unless response['type'] == 'response.audio.delta' && response['delta']

          begin
            audio_payload = response['delta']
            @audio_queue.enqueue(
              audio_payload
            )
          rescue StandardError => e
            @logger.info "Error processing audio data: #{e}"
          end
        end
      end

      # Make sure the connection is closed at least two seconds before the next session begins
      task.sleep(ENV['SESSION_DURATION_IN_MINUTES'].to_i.minutes - 2.seconds)

      @logger.info 'Connection closed with OpenAI'

      inbound_message_task.stop
      message_reader_task.stop
      audio_out_task.stop
    ensure
      @pipe.close
      @connection.close
    end
  end

  def process_inbound_messages
    @logger.info 'Processing inbound messages'
    Async do
      loop do
        message = @inbound_message_queue.dequeue

        openai_message = Protocol::WebSocket::TextMessage.generate(JSON.parse(message))
        openai_message.send(@connection)
        @connection.flush
      end
    end
  end
end
