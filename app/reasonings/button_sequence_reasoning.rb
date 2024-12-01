class ButtonSequenceReasoning < BaseSchema
  def initialize
    super do
      define :button do
        enum :button, %w[Up Down Left Right A B]
      end

      string :image_description
      string :explanation

      string :button

      # array :button_sequence, items: ref(:button)
    end
  end
end
