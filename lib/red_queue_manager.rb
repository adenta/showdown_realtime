class RedQueueManager
  attr_accessor :goal_updates

  def initialize
    @goal_updates = QueueWithEmpty.new
  end
end
