namespace :faye do
  task vibe: :environment do
    pokemon_showdown_message_queue = []
    openai_message_queue = []
    file_path = Rails.root.join('log', 'commands.log')
    file = File.open(file_path, 'r')
    file.seek(0, IO::SEEK_END) # Move to the end of the file
    log_filename = Rails.root.join('log', 'demo.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'CONSOLE'

    EM.run do
      OpenaiWebsocketServiceFaye.new(
        openai_message_queue,
        pokemon_showdown_message_queue
      ).open_connection

      PokemonShowdownWebsocketServiceFaye.new(
        pokemon_showdown_message_queue,
        openai_message_queue
      ).open_connection

      EM.defer do
        loop do
          line = file.gets
          if line

            openai_message_queue << ({
              "type": 'conversation.item.create',
              "item": {
                "type": 'message',
                "role": 'user',
                "content": [
                  {
                    "type": 'input_text',
                    "text": "chairlaw: #{line.strip}"
                  }
                ]
              }
            }.to_json)
            openai_message_queue << ({
              "type": 'response.create'
            }.to_json)
          else
            sleep 1 # Sleep for a second if no new line is found
          end
        end
      end
    end
  end

  task vibe_over_stdout: :environment do
    command = 'SEND_AUDIO_TO_STDOUT=true rails async:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1  -strict experimental -analyzeduration 0 -probesize 32 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'
    system(command)
  end

  task send_commands: :environment do
    Async do |task|
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
