# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class GoalSettingService
  attr_reader :goal

  def initialize(queue_manager)
    log_filename = Rails.root.join('log', 'asyncstreamer-red.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'GOAL'

    @queue_manager = queue_manager
    @goal = nil
  end

  def read_messages_from_queue_task
    Async do
      loop do
        message = @queue_manager.goal_updates.dequeue

        @goal = message[:goal]
      end
    end
  end
end
