class FakeChatService
  def self.generate_messages(battle_state)
    # Create an OpenAI client
    client = SchemaClient.new
    # Create an instance of the MathReasoning schema
    schema = FakeChatReasoning.new

    result = client.parse(
      model: 'gpt-4o',
      messages: [
        { role: 'system',
          content: <<~HEREDOC
            You are a producer at a twitch streaming company. The twitch streamer is playing pokemon and is getting suggestions from her chat.

            Here is the state of the battle: #{battle_state}

            You need to come up with test data about what users in chat might say. Include at least 10 messages.
          HEREDOC
        }
      ],
      response_format: schema
    )

    # Handle the response
    if result.refusal
      nil

    else
      result.parsed

    end
  rescue StandardError => e
    puts "Error: #{e}"
  end
end
