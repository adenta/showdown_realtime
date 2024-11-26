namespace :red do
  task complete: :environment do
    client = SchemaClient.new
    # Create an instance of the MathReasoning schema
    schema = FakeChatReasoning.new

    response = client.parse(
      model: 'gpt-4o',
      response_format: schema,
      messages: [{ role: 'user',
                   content: 'generate some fake chat messages' }]
    )

    puts response.parsed
  end
end
