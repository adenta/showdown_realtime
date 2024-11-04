namespace :async do
  task vibe: :environment do
    pokemon_showdown_message_queue = Async::Queue.new
    openai_message_queue = Async::Queue.new
    reader = IO::Stream::Buffered.new($stdin)

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
        while (line = reader.read_until("\n"))
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
        end
      end
    end
  end

  task obs: :environment do
    Async do
      ObsWebsocketService.new.open_connection
    end
  end
end
