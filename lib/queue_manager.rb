class QueueManager
  attr_accessor :pokemon_showdown, :openai, :openai_command, :audio_out

  def initialize
    @pokemon_showdown = QueueWithEmpty.new
    @openai = QueueWithEmpty.new
    @openai_command = QueueWithEmpty.new
    @audio_out = QueueWithEmpty.new
  end
end
