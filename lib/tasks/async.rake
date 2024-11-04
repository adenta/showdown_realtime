namespace :async do
  task vibe: :environment do
    pokemon_showdown_message_queue = Async::Queue.new
    openai_message_queue = Async::Queue.new
    file_path = Rails.root.join('log', 'commands.log')
    file = File.open(file_path, 'r')
    file.seek(0, IO::SEEK_END) # Move to the end of the file

    Async do |task|
      ObsWebsocketService.new.open_connection

      OpenaiWebsocketService.new(
        openai_message_queue,
        pokemon_showdown_message_queue
      ).open_connection

      PokemonShowdownWebsocketService.new(
        pokemon_showdown_message_queue,
        openai_message_queue
      ).open_connection

      task.async do
        loop do
          line = file.gets
          if line

            openai_message_queue.enqueue({
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
            openai_message_queue.enqueue({
              "type": 'response.create'
            }.to_json)
          else
            task.sleep 1 # Sleep for a second if no new line is found
          end
        end
      end
    end
  end

  task vibe_over_stdout: :environment do
    command = 'SEND_AUDIO_TO_STDOUT=true rails async:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'
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
