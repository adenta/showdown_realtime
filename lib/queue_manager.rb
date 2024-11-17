class QueueManager
  attr_accessor :pokemon_showdown, :openai, :openai_function, :audio_out, :obs

  def initialize
    @pokemon_showdown = QueueWithEmpty.new
    @openai = QueueWithEmpty.new
    @openai_function = QueueWithEmpty.new
    @audio_out = QueueWithEmpty.new
    @obs = QueueWithEmpty.new

  end
end
