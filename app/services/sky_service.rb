# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class SkyService
  def initialize(queue_manager, goal_setting_service)
    log_filename = Rails.root.join('log', 'asyncstreamer-red.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'GOAL'

    @queue_manager = queue_manager
    @goal_setting_service = goal_setting_service
  end

  def send_messages_to_sky_task
    Async do |task|
      loop do
        @logger.info "The current goal is #{@goal_setting_service.goal}"
        task.sleep 1
      end
    end
  end
end
