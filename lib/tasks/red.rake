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

        goal_setting_service = GoalSettingService.new(queue_manager)
        sky_service = SkyService.new(queue_manager, goal_setting_service)

        RedCommandSendingService.new(queue_manager).launch

        goal_setting_service.read_messages_from_queue_task
        sky_service.send_messages_to_sky_task

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

  task tile_data: :environment do
    # SkyEmu server configuration

    # Main execution

    # Example: Read 16 bytes of VRAM starting from 0x06000000
    address = 0x02031dfc
    start_time = Time.now
    memory_data = RetroarchGbaMemoryReaderMultiByte.new.read_bytes(address, 0x2800)
    end_time = Time.now

    grid = memory_data.each_slice(78).to_a

    byte_grid = grid.map do |row|
      row.each_slice(2).to_a
    end

    formatted_grid = byte_grid.map do |row|
      row.reject { |pair| pair == %w[FF 03] }
    end

    full_map = formatted_grid.reject!(&:empty?)

    tilemap = full_map.map do |row|
      row.map do |pair|
        cell = pair.reverse.join

        binary_string = cell.to_i(16).to_s(2).rjust(16, '0').split('').reverse
        colission = binary_string[10..11]
        case colission
        when %w[0 0]
          ' '
        when %w[0 1]
          '1'
        when %w[1 0]
          '2'
        when %w[1 1]
          '3'
        end
      end
    end

    puts tilemap.map(&:join).join("\n")
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end
