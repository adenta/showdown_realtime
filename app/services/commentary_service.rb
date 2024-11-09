# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class CommentaryService
  def initialize(inbound_message_queue)
    @battle_state = {}
    @inbound_message_queue = inbound_message_queue
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'COMM'
    @messages = []
  end

  def open_connection
    Async do |task|
      process_inbound_messages
    end

    # Async do
    #   loop do
    #     @logger.info 'Generating Commentary'
    #     message_buffer_string = <<~TXT
    #       You are providing commentary for a game of pokemon.#{' '}

    #       This is what everyone is suggesting, and the moves that have been used: #{@messages.join(' ')}
    #     TXT

    #     base64_response = OpenaiVoiceService.new.generate_voice(message_buffer_string)
    #     audio_response = Base64.decode64(base64_response)
    #     STDOUT.write(audio_response)
    #     STDOUT.flush
    #     @logger.info 'Finished Generating Commentary'
    #   end
    # end
  end

  def process_inbound_messages
    Async do
      loop do
        message = @inbound_message_queue.dequeue
        @logger.info "Received message of type: #{message[:type]}"
        @logger.info "Message Was created at: #{message[:created_at]}"

        @logger.info "Message data: #{message[:data].first(20)}..."
      end
    end
  end
end
