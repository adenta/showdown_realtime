class FakeChatReasoning < BaseSchema
  def initialize
    super do
      define :chat_message do
        string :username
        string :body
      end
      array :chat_messages, items: ref(:chat_message)
    end
  end
end
