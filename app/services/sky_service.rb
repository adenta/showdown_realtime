# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

class FixedQueue
  def initialize(max_size)
    @max_size = max_size
    @queue = []
  end

  def add(element)
    @queue.shift if @queue.size >= @max_size
    @queue << element
  end

  def elements
    @queue
  end
end

class SkyService
  HOST = 'http://localhost:9043'
  SCREEN_ENDPOINT = "#{HOST}/screen"
  INPUT_ENDPOINT = "#{HOST}/input"

  def initialize(queue_manager, goal_setting_service)
    log_filename = Rails.root.join('log', 'asyncstreamer-red.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'GOAL'

    @queue_manager = queue_manager
    @goal_setting_service = goal_setting_service
  end

  def send_messages_to_sky_task
    fixed_queue = FixedQueue.new(5)
    Async do |task|
      loop do
        task.sleep 1

        goal = @goal_setting_service.goal

        next unless goal.present?

        client = SchemaClient.new
        # Create an instance of the MathReasoning schema
        schema = ButtonSequenceReasoning.new

        system_prompt = <<~TXT
          You are a pokemon master.

          You will be given a partially completed game.
          After seeing it, you should choose the next moves, when considering you want to accomplish #{goal}.

          You cant walk or interact diagonally.
        TXT

        response = client.parse(
          model: 'gpt-4o',
          response_format: schema,
          messages: [
            { role: 'system', content: system_prompt },
            { role: 'user',
              content: [
                { "type": 'image_url',
                  "image_url": {
                    "url": fetch_base64_screen
                  } },
                { type: 'text',
                  text: fixed_queue.elements.map { |e| e[:message] }.join(', ') }
              ] }
          ]
        )

        response.parsed['button_sequence'].each do |button_command|
          button = button_command['button']

          fixed_queue.add(button_command)

          Net::HTTP.get(URI("#{INPUT_ENDPOINT}?#{button}=1"))
          task.sleep 0.2
          Net::HTTP.get(URI("#{INPUT_ENDPOINT}?#{button}=0"))
        end
      end
    end
  end

  private

  def fetch_base64_screen
    uri = URI(SCREEN_ENDPOINT)
    response = Net::HTTP.get(uri)
    base64_image = Base64.encode64(response)
    "data:image/png;base64,#{base64_image}"
  end
end
