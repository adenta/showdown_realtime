namespace :redfirst do
  task complete: :environment do
    endpoint = 'http://localhost:9043/screen'

    uri = URI(endpoint)
    response = Net::HTTP.get(uri)
    base64_image = Base64.encode64(response)
    image_data_url = "data:image/png;base64,#{base64_image}"

    client = OpenAI::Client.new
    # Create an instance of the MathReasoning schema
    schema = ButtonSequenceReasoning.new

    system_prompt = <<~TXT
      You are a pokemon master.#{'      '}

      given the image and a destination, write out a series of moves along the grid (each tile is 16 by 16 pixels if thats helpful) that will get you to your destination.#{' '}

      give directions in terms of steps north, south, east and west (north is up).

      remember, you cant phase through walls, and you cant walk diagonally. You will need to walk around objects.

      you will not have reached your destination until you are standing directly north, south, east, or west of it.

    TXT

    user_prompt = <<~TXT
      destination: the mailbox
    TXT
    response = client.chat(
      parameters: {
        model: 'gpt-4o',
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
      }
    )

    puts response['choices'][0]['message']['content']
  end
end
