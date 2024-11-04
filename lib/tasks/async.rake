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
            puts "Received: #{line.strip}"

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

  # lib/tasks/fiber_stream.rake

  task stream: :environment do
    fiber = Fiber.new do
      data_to_send = %W[part1\n part2\n part3\n]
      data_to_send.each { |data| Fiber.yield(data) }
    end

    Async do
      File.open(Rails.root.join('log', 'outputtest.log'), 'a') do |file|
        while fiber.alive?
          data = fiber.resume
          file.write(data)
          file.flush
          Async::Task.current.sleep 1
        end
      end
    end
  end

  task audio: :environment do
    Async do |task|
      task.async do
        IO.popen(['ffmpeg', '-f', 'lavfi', '-i', 'anoisesrc=d=10:c=pink', '-f', 'wav', 'pipe:1'],
                 'r') do |ffmpeg_io|
          IO.popen(
            ['ffmpeg', '-f', 's16le', '-ar', '24000', '-ac', '1', '-readrate', '1', '-fflags', 'nobuffer', '-flags', 'low_delay',
             '-strict', 'experimental', '-analyzeduration', '0', '-probesize', '32', '-i', 'pipe:0', '-c:a', 'aac', '-ar', '44100', '-ac', '1', '-f', 'flv', 'rtmp://localhost:1935/live/stream'], 'w'
          ) do |output_io|
            output_io.binmode # Ensures binary mode, avoiding encoding errors
            while (chunk = ffmpeg_io.read(4096))
              output_io.write(chunk)
              output_io.flush
            end
          end
        end
      end

      task.async do
        puts Time.zone.now
        task.sleep 1
      end
    end
  end

  task read_from_file: :environment do
    Async do |task|
      file_path = Rails.root.join('log', 'commands.log')
      file = File.open(file_path, 'r')
      file.seek(0, IO::SEEK_END) # Move to the end of the file

      task.async do
        loop do
          line = file.gets
          if line
            puts "New line: #{line.strip}"
          else
            task.sleep 1 # Sleep for a second if no new line is found
          end
        end
      end
    end
  end

  task write_to_file: :environment do
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
