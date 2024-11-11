class QueueManager
  attr_accessor :pokemon_showdown, :openai, :audio_out

  def initialize
    @pokemon_showdown = QueueWithEmpty.new
    @openai = QueueWithEmpty.new
    @audio_out = QueueWithEmpty.new
  end
end
