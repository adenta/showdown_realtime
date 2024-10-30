namespace :async do
  task vibe: :environment do
    pokemon_showdown_message_queue = Async::Queue.new
    openai_message_queue = Async::Queue.new

    Async do
      ObsWebsocketService.new.open_connection
      OpenaiWebsocketService.new(
        pokemon_showdown_message_queue,
        openai_message_queue
      ).open_connection

      PokemonShowdownWebsocketService.new(
        openai_message_queue,
        pokemon_showdown_message_queue
      ).open_connection
    end
  end
end
