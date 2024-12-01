class SkyGbaMemoryReader
  SERVER_ADDRESS = 'localhost'
  SERVER_PORT = 9043

  def initialize
  end

  def read_bytes(address, length)
    read_memory(address, length)
  end

  private

  # Helper method to send HTTP requests
  def send_request(endpoint, addresses)
    uri = URI("http://#{SERVER_ADDRESS}:#{SERVER_PORT}#{endpoint}?addr=")
    uri.query = addresses.join('&addr=')

    response = Net::HTTP.get_response(uri)
    raise "Request failed: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  # Read memory from a specific address
  def read_memory(address, length)
    addresses = length.times.map { |n| (address + n).to_s(16) }
    puts "Reading memory from 0x#{address.to_s(16)} (#{length} bytes)..."
    send_request('/read_byte', addresses)
  end
end
