namespace :async do
  task vibe: :environment do
    queue_manager = QueueManager.new

    Async do |task|
      # OpenAI times out at fifteen minutes, so we must periodically restart the service
      loop do
        # openai_voice_service = OpenaiVoiceService.new(queue_manager)
        openai_function_service = OpenaiFunctionService.new(queue_manager)

        # openai_voice_service.read_messages_from_openai_task
        # openai_voice_service.read_messages_from_queue_task
        # openai_voice_service.stream_audio_task
        openai_function_service.read_messages_from_openai_task
        openai_function_service.read_messages_from_queue_task

        PokemonShowdownWebsocketService.new(
          queue_manager
        ).open_connection

        CommandSendingService.new(queue_manager.openai_command).launch

        task.sleep(ENV['SESSION_DURATION_IN_MINUTES'].to_i.minutes)
      ensure
        # openai_voice_service.close_connections
        openai_function_service.close_connections
      end
    end
  end

  task send_commands: :environment do
    Async do |task|
      # TODO(adenta) magic string commands.log
      file_path = Rails.root.join('log', 'commands.log')
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
