class ButtonSequenceReasoning < BaseSchema
  def initialize
    super do
      define :button do
        enum :button, %w[Up Down Left Right A B]
      end
      array :button_sequence, items: ref(:button)
      string :explanation
    end
  end
end
