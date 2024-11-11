namespace :async do
  task vibe: :environment do
    pokemon_showdown_message_queue = Async::Queue.new
    openai_message_queue = Async::Queue.new
    audio_queue = QueueWithEmpty.new

    Async do |task|
      PokemonShowdownWebsocketService.new(
        pokemon_showdown_message_queue,
        openai_message_queue,
        audio_queue
      ).open_connection

      CommandSendingService.new(openai_message_queue).launch

      # OpenAI times out at fifteen minutes, so we must periodically restart the service
      loop do
        OpenaiWebsocketService.new(
          openai_message_queue,
          pokemon_showdown_message_queue,
          audio_queue
        ).open_connection

        task.sleep(ENV['SESSION_DURATION_IN_MINUTES'].to_i.minutes)
      end
    end
  end

  task vibe_over_rtmp: :environment do
    # command = 'SEND_AUDIO_TO_STDOUT=true rails async:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1  -fflags nobuffer -flags low_delay -strict experimental -analyzeduration 0 -probesize 32 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'

    command = 'SEND_AUDIO_TO_STDOUT=true rails async:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1  -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'

    system(command)
  end

  task vibe_over_ffplay: :environment do
    command = 'SEND_AUDIO_TO_STDOUT=true rails async:vibe | ffplay -f s16le -ar 24000 -fflags nobuffer -flags low_delay -i pipe:0'
    system(command)
  end

  task audio_test: :environment do
    response = OpenaiVoiceService.new.generate_voice(<<~TXT)
      Turn 6

      Magneton used Thunder Wave!
      The opposing Parasect is paralyzed! It may be unable to move!

      The opposing Parasect is paralyzed! It can't move!

      Turn 7

      Magneton used Thunder!
      It's not very effective...
      (The opposing Parasect lost 30% of its health!)

      The opposing Parasect used Hyper Beam!
      (Magneton lost 17.2% of its health!)

      Magneton fainted!

      Go! Tentacruel!
    TXT
    audio_response = Base64.decode64(response)
    filename = Rails.root.join('tmp', "#{Time.now.strftime('%Y%m%d%H%M%S')}.wav")
    File.open(filename, 'wb') do |file|
      file.write(audio_response)
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
