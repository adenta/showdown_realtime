class OpenaiVoiceService
  def initialize
    @client = OpenAI::Client.new
    log_filename = Rails.root.join('log', 'asyncstreamer.log')
    @logger = ColorLogger.new(log_filename)
    @logger.progname = 'VOCIN'
  end

  def generate_voice(text)
    # gpt-4o-audio-preview
    response = @client.chat(
      parameters: {
        model: 'gpt-4o-audio-preview',
        modalities: %w[text audio],
        audio: { voice: 'ash', format: 'wav' },
        messages: [
          {
            role: 'user',
            content: text
          }
        ]
      }
    )

    response['choices'][0]['message']['audio']['data']
  end
end
