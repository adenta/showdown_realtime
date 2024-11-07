namespace :async do
  task vibe: :environment do
    pokemon_showdown_message_queue = Async::Queue.new
    openai_message_queue = Async::Queue.new

    Async do |task|
      PokemonShowdownWebsocketService.new(
        pokemon_showdown_message_queue,
        openai_message_queue
      ).open_connection(fake_messages: true)

      CommandSendingService.new(openai_message_queue).launch

      # OpenAI times out at fifteen minutes, so we must periodically restart the service
      loop do
        OpenaiWebsocketService.new(
          openai_message_queue,
          pokemon_showdown_message_queue
        ).open_connection

        task.sleep(ENV['SESSION_DURATION_IN_MINUTES'].to_i.minutes)
      end
    end
  end

  task vibe_over_rtmp: :environment do
    # command = 'SEND_AUDIO_TO_STDOUT=true rails async:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1  -fflags nobuffer -flags low_delay -strict experimental -analyzeduration 0 -probesize 32 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'

    command = 'SEND_AUDIO_TO_STDOUT=true rails async:vibe | ffmpeg -f s16le -ar 24000 -ac 1 -readrate 1 -i pipe:0 -c:a aac -ar 44100 -ac 1 -f flv rtmp://localhost:1935/live/stream'

    system(command)
  end

  task vibe_over_ffplay: :environment do
    command = 'SEND_AUDIO_TO_STDOUT=true rails async:vibe | ffplay -f s16le -ar 24000 -fflags nobuffer -flags low_delay -i pipe:0'
    system(command)
  end
end
