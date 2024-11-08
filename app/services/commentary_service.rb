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
  end

  def open_connection
    Async do |task|
      process_inbound_messages
    end
  end

  def process_inbound_messages
    Async do
      loop do
        @logger.info 'Processing Commentary Track'
        message = @inbound_message_queue.dequeue

        @logger.info message
      end
    end
  end
end
