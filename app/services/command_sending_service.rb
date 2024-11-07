class CommandSendingService
  def initialize(openai_message_queue)
    @openai_message_queue = openai_message_queue
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'COMM'

    file_path = Rails.root.join('log', 'commands.log')
    @file = File.open(file_path, 'r')
    @file.seek(0, IO::SEEK_END) # Move to the end of the file
  end

  def launch
    Async do |task|
      loop do
        line = @file.gets
        if line

          @openai_message_queue.enqueue({
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
          @openai_message_queue.enqueue({
            "type": 'response.create'
          }.to_json)
        else
          task.sleep 1 # Sleep for a second if no new line is found
        end
      end
    end
  end
end
