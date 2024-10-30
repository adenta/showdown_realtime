namespace :obs do
  task switch_scenes: :environment do
    openai_inbound_message_queue = Async::Queue.new
    openai_outbound_message_queue = Async::Queue.new

    Async do
      ObsWebsocketService.new.open_connection
      OpenaiWebsocketService.new(
        openai_inbound_message_queue,
        openai_outbound_message_queue
      ).open_connection
    end
  end
end
