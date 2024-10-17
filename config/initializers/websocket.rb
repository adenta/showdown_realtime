# config/initializers/openai_websocket.rb
require 'faye/websocket'
require 'json'
require 'base64'

Thread.new do
  openai_ws = Faye::WebSocket::Client.new('wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01', nil, {
                                            headers: {
                                              'Authorization' => "Bearer #{ENV['OPENAI_API_KEY']}",
                                              'OpenAI-Beta' => 'realtime=v1'
                                            }
                                          })

  openai_ws.on :open do |event|
    Rails.logger.info 'Connected to OpenAI WebSocket'
  end

  openai_ws.on :message do |event|
    response = JSON.parse(event.data)
    Rails.logger.info "Received message: #{response}"
  end

  openai_ws.on :error do |event|
    Rails.logger.error "WebSocket Error: #{event.message}"
  end

  openai_ws.on :close do |event|
    Rails.logger.info "Connection closed: #{event.code} - #{event.reason}"
  end

  # Keep the thread running
  loop do
    sleep 1
  end
end
