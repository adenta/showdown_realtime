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

    Drop in an add for the vermillion city pokemart every so often. They have a sale on hyper potions, three for five hundred poke bucks.
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
      'temperature': 1
    }
  }.freeze

  def initialize(inbound_message_queue, outbound_message_queue, commentary_message_queue, audio_queue)
    @endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: Async::HTTP::Protocol::HTTP11.names)
    @inbound_message_queue = inbound_message_queue
    @outbound_message_queue = outbound_message_queue
    @commentary_message_queue = commentary_message_queue
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'OPENAI'
    @audio_queue = audio_queue
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

        audio_out_task = task.async do |subtask|
          loop do
            audio_out = @audio_queue.dequeue

            @logger.info "Audio length: #{audio_out[:audio_length_ms]}"

            if ENV['SEND_AUDIO_TO_STDOUT'] == 'true'
              STDOUT.write(audio_out[:decoded_audio])
              STDOUT.flush
            end

            subtask.sleep(audio_out[:audio_length_ms] * 0.8 / 1000)
          end
        end

        message_reader_task = task.async do |subtask|
          @logger.info 'Reading Messages from OpenAI'

          while (message = connection.read)
            response = JSON.parse(message)

            @logger.info response if response['type'] == 'error' || response['type'] == 'rate_limits.updated'

            function_call = response['type'].include? 'response.function_call_arguments.done'

            if function_call && response['name'] == 'choose_move'
              choose_move(connection, response)
            elsif function_call && response['name'] == 'switch_pokemon'
              switch_pokemon(connection, response)
            elsif response['type'] == 'response.text'
              @logger.info response
            elsif response['type'] == 'response.audio.delta' && response['delta']

              @logger.info response['type']

              begin
                # Base64 encoced PCM packets
                audio_payload = response['delta']

                decoded_audio = Base64.decode64(audio_payload)

                audio_length_ms = (decoded_audio.length / 2.0 / 24_000) * 1000

                @audio_queue.enqueue(
                  {
                    decoded_audio: decoded_audio,
                    audio_length_ms: audio_length_ms
                  }
                )
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
        audio_out_task.stop
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
    args = response['arguments']
    json_args = JSON.parse(args)

    switch_name = json_args['switch_name']
    @outbound_message_queue.enqueue({ type: 'switch_pokemon', switch_name: switch_name })
  end
end
