namespace :async do
  task vibe: :environment do
    pokemon_showdown_message_queue = Async::Queue.new
    openai_message_queue = Async::Queue.new

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
          sleep 2.seconds
          pokemon_showdown_message_queue.enqueue({ type: 'default' })
          # openai_message_queue.enqueue({
          #   "type": 'conversation.item.create',
          #   "item": {
          #     "type": 'message',
          #     "role": 'user',
          #     "content": [
          #       {
          #         "type": 'input_text',
          #         "text": 'andre: use earthquake'
          #       }
          #     ]
          #   }
          # }.to_json)
          # openai_message_queue.enqueue({
          #   "type": 'response.create'
          # }.to_json)
        end
      end
    end
  end
end
