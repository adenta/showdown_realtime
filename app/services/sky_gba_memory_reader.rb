class SkyGbaMemoryReader
  SERVER_ADDRESS = 'localhost'
  SERVER_PORT = 9043

  def initialize
  end

  def read_bytes(address, length)
    uri = URI("http://#{SERVER_ADDRESS}:#{SERVER_PORT}/read_byte")

    addrs = (address...(address + length)).map { |addr| "addr=#{addr.to_s(16)}" }

    uri.query = addrs.join('&')

    puts uri

    response = Net::HTTP.get_response(uri)
    raise "Request failed: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end
end
