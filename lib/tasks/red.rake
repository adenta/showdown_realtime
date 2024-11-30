namespace :red do
  task vibe: :environment do
    goal = 'talk to mom'
    queue_manager = RedQueueManager.new

    @logger = ColorLogger.new(Rails.root.join('log', 'asyncstreamer-red.log'))
    @logger.progname = 'ASYN'

    Async do |task|
      # OpenAI times out at fifteen minutes, so we must periodically restart the service
      loop do
        @logger.info 'Starting Services'

        RedCommandSendingService.new(queue_manager).launch

        task.sleep(ENV['SESSION_DURATION_IN_MINUTES'].to_i.minutes)
      ensure
        @logger.info 'Shutting Down Services'
      end
    end
  end

  task send_commands: :environment do
    Async do |task|
      # TODO(adenta) magic string commands.log
      file_path = Rails.root.join('log', 'commands-red.log')
      File.open(file_path, 'a') do |file|
        loop do
          puts "Enter a message to log (or type 'exit' to quit):"
          input = STDIN.gets.strip
          break if input.downcase == 'exit'

          file.puts input
          file.flush
        end
      end
    end
  end
end
