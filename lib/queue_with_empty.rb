class QueueWithEmpty < Async::Queue
  def clear
    @items.clear
  end
end
