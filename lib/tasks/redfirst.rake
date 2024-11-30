namespace :redfirst do
  task complete: :environment do
    endpoint = 'http://localhost:9043/screen'

    uri = URI(endpoint)
    response = Net::HTTP.get(uri)
    base64_image = Base64.encode64(response)
    image_data_url = "data:image/png;base64,#{base64_image}"

    client = SchemaClient.new
    # Create an instance of the MathReasoning schema
    schema = ButtonSequenceReasoning.new

    system_prompt = <<~TXT
      You are a streamer playing a game of pokemon. You will be playing the game
      based on feedback from your audiance of 4 million subscribers.

      You cant walk or interact diagonally
    TXT

    user_prompt = <<~TXT
      talk to mom
    TXT
    response = client.parse(
      model: 'gpt-4o',
      response_format: schema,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user',
          content: [
            { "type": 'image_url',
              "image_url": {
                "url": image_data_url
              } },
            { type: 'text',
              text: user_prompt }
          ] }
      ]
    )

    response.parsed['button_sequence'].each do |b|
      button = b['button']
      puts button

      url = "http://localhost:9043/input?#{button}=1"
      Net::HTTP.get(URI(url))
      sleep 0.2
      url = "http://localhost:9043/input?#{button}=0"
      Net::HTTP.get(URI(url))
    end
  end
end
