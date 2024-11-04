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

# task stdin_testing: :environment do
#   Curses.init_screen
#   Curses.curs_set(0) # Hide cursor for log area

#   begin
#     log_win = Curses::Window.new(Curses.lines - 1, Curses.cols, 0, 0)
#     input_win = Curses::Window.new(1, Curses.cols, Curses.lines - 1, 0)

#     log_win.scrollok(true)
#     log_win.idlok(true)
#     reader = IO::Stream::Buffered.new($stdin)

#     Async do |task|
#       # Async task for WebSocket logs
#       task.async do
#         loop do
#           # Simulate log event
#           log_win.addstr("Log message at #{Time.now}\n")
#           log_win.refresh
#           task.sleep(1) # Replace with real log event triggers
#         end
#       end

#       # Input handling loop
#       input_win.setpos(0, 0)
#       input_win.addstr('Enter command: ')
#       input_win.refresh
#       Curses.curs_set(1)

#       task.async do
#         while (line = reader.read_until("\n"))
#           log_win.addstr("Received input: #{line}\n")
#           log_win.refresh
#           input_win.clear
#           input_win.setpos(0, 0)
#           input_win.addstr('Enter command: ')
#           input_win.refresh
#         end
#       end
#     end
#   ensure
#     Curses.close_screen
#   end
# end

# task stdin_testing: :environment do
#   Async do |task|
#     ObsWebsocketService.new.open_connection

#     reader = IO::Stream::Buffered.new($stdin)

#     task.async do
#       while (line = reader.read_until("\n"))
#         puts "Received: #{line.strip}"
#       end
#     end
#   end

# prompt = TTY::Prompt.new
# cursor = TTY::Cursor

# Async do |task|
#   ObsWebsocketService.new.open_connection

#   # Task to handle user input
#   task.async do
#     loop do
#       line = prompt.ask('Enter input:')
#       break unless line

#       puts "Received: #{line.strip}"
#     end
#   end
