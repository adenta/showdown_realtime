# frozen_string_literal: true

require 'async'
require 'async/http'
require 'async/websocket'

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
    Async do |task|
      loop do
        goal = @goal_setting_service.goal

        if goal.nil?
          task.sleep 1
          next
        end

        client = SchemaClient.new
        # Create an instance of the MathReasoning schema
        schema = ButtonSequenceReasoning.new

        system_prompt = <<~TXT
          You are a pokemon master.

          You will be given a partially completed game.
          After seeing it, you should choose the next moves, when considering you want to accomplish the goal: "#{goal}".

          You cant walk or interact diagonally. finish conversations quickly, so you can get back to accomplishing your goals.
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
                  } }
              ] }
          ]
        )

        button = response.parsed['button']

        Net::HTTP.get(URI("#{INPUT_ENDPOINT}?#{button}=1"))
        task.sleep 0.2
        Net::HTTP.get(URI("#{INPUT_ENDPOINT}?#{button}=0"))

        # response.parsed['button_sequence'].each do |button_command|
        #   button = button_command['button']

        #   Net::HTTP.get(URI("#{INPUT_ENDPOINT}?#{button}=1"))
        #   task.sleep 0.2
        #   Net::HTTP.get(URI("#{INPUT_ENDPOINT}?#{button}=0"))
        # end
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
