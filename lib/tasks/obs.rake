namespace :obs do
  task switch_scenes: :environment do
    ObsWebsocketService.new.open_connection
  end
end
