require 'async'
require 'async/barrier'
class SkyGbaMemoryReader
  SERVER_ADDRESS = 'localhost'
  SERVER_PORT = 9043

  def initialize
  end

  def read_bytes(address, length)
    memory_data = []
    batch_size = 100
    Async do |task|
      barrier = Async::Barrier.new

      (0...length).step(batch_size) do |i|
        barrier.async do
          batch_address = address + i
          batch_length = [batch_size, length - i].min
          memory_data[i, batch_length] = read_memory_batch(batch_address, batch_length)
        end
      end

      barrier.wait
      memory_data.join
    end

    memory_data.join
  end

  private

  # Helper method to send HTTP requests
  def send_request(address, length = 1)
    uri = URI("http://#{SERVER_ADDRESS}:#{SERVER_PORT}/read_byte")

    uri.query =
      if length > 1
        addresses = (address...(address + length)).map { |addr| "addr=#{addr.to_s(16)}" }

        addresses.join('&')
      else
        URI.encode_www_form(addr: address.to_s(16))
      end

    response = Net::HTTP.get_response(uri)
    raise "Request failed: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  # Read memory from a specific address
  def read_memory(address)
    send_request(address)
  end

  # Read memory from a specific address
  def read_memory_batch(address, length)
    send_request(address, length)
  end
end
