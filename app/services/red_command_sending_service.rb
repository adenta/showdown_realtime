class RedCommandSendingService
  def initialize(queue_manager)
    @queue_manager = queue_manager

    log_filename = Rails.root.join('log', 'asyncstreamer-red.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'COMM'

    file_path = Rails.root.join('log', 'commands-red.log')
    @file = File.open(file_path, 'r')
    @file.seek(0, IO::SEEK_END) # Move to the end of the file
  end

  def launch
    Async do |task|
      @logger.info 'Command sending service started'
      loop do
        line = @file.gets
        if line
          @queue_manager.goal_updates.enqueue({
                                                goal: line.strip
                                              })

        else
          task.sleep 1 # Sleep for a second if no new line is found
        end
      end
    end
  end
end
