# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class OpenaiVoiceService
  URL = 'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview'
  HEADERS = {
    'Authorization': "Bearer #{ENV.fetch('OPENAI_API_KEY', nil)}",
    'OpenAI-Beta': 'realtime=v1'
  }.freeze

  INSTRUCTIONS = <<~TXT
    You are a Buzz Alderman, a male, 34 year old old timey radio host, broadcasting a match of pokemon. You are the best radio host this side of the mason dixon.
    Keep each of your responses to twenty words or less. 
    
    Be sure to keep the energy high and the excitement palpable. Really lean into having a winning personality, keeping people engaged. You are an expert in keeping people hanging on your every word.
    
    Only occasionally list out the moves that can be switched to. Never mention what turn it is by the turn number.
  TXT

  SESSION_UPDATE = {
    'type': 'session.update',
    'session': {
      'input_audio_format': 'pcm16',
      'output_audio_format': 'pcm16',
      'voice': 'ash',
      'instructions': INSTRUCTIONS,
      'modalities': %w[text audio],
      'temperature': 1
    }
  }.freeze

  def initialize(queue_manager)
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'OAIVO'

    endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
    @connection = Async::WebSocket::Client.connect(endpoint, headers: HEADERS)
    @logger.info 'Connection established to OpenAI'

    @inbound_message_queue = queue_manager.openai
    @outbound_message_queue = queue_manager.pokemon_showdown
    @queue_manager = queue_manager
    @audio_queue = queue_manager.audio_out

    # @pipe = IO.popen(
    #   'ffmpeg -f s16le -ar 24000 -ac 1 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream', 'wb' # Changed 'w' to 'wb'
    # )

    @pipe = IO.popen(
  'ffmpeg -f s16le -ar 24000 -ac 1 -i pipe:0 -af "lowpass=f=3000,highpass=f=300,aresample=44100:resampler=soxr,compand=gain=-10,anlmdn=m=1,alimiter=limit=0.8" -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream', 'wb'
)

    session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
    session_update_message.send(@connection)
    @connection.flush

    session_update_message = Protocol::WebSocket::TextMessage.generate(SESSION_UPDATE) # ({ text: line })
    session_update_message.send(@connection)
    @connection.flush
  end

  def read_messages_from_openai_task
    Async do |task|
      @logger.info 'Reading Messages from OpenAI'

      while (message = @connection.read)
        response = JSON.parse(message)

        @logger.info response['type'] 

        next unless response['type'] == 'response.audio.delta' && response['delta']

        begin
          audio_payload = response['delta']

          @queue_manager.audio_out.enqueue(
            audio_payload
          )
        rescue StandardError => e
          @logger.info "Error processing audio data: #{e}"
        end
      end
    end
  end

  def read_messages_from_queue_task
    Async do
      loop do
        message = @queue_manager.openai.dequeue

        openai_message = Protocol::WebSocket::TextMessage.generate(JSON.parse(message))
        openai_message.send(@connection)
        @connection.flush
      end
    end
  end

  def stream_audio_task
    Async do |task|
      loop do
        audio_payload = @queue_manager.audio_out.dequeue

        decoded_audio = Base64.decode64(audio_payload)
        audio_length_ms = (decoded_audio.length / 2.0 / 24_000) * 1000

        @pipe.write(decoded_audio)
        @pipe.flush

        task.sleep((audio_length_ms * ENV['AUDIO_BUFFER_PERCENTAGE'].to_f) / 1000)
      end
    end
  end

  def close_connections
    @pipe.close
    @connection.close
  end
end
