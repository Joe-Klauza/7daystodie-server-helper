require 'socket'
require 'io/nonblock'
require_relative 'logger'

class TelnetClient
  include Logging
  READ_SIZE = 1024*10
  SERVER_LOG_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} / # '2020-01-01T00:00:00 '

  def initialize(hostname, port)
    @hostname = hostname
    @port = port
  end

  def send(command)
    # Create a TCP socket and connect to the Telnet server
    socket = TCPSocket.new(@hostname, @port)
    socket.nonblock = true
    # Send the command, followed by a newline and our endcommand to detect end of response
    socket.puts("startcommand\n")
    socket.puts("#{command}\n")
    socket.puts("endcommand\n")
    response = ""
    header_finished = false
    # Read the response in a non-blocking way
    begin
      loop do
        begin
          data = socket.read_nonblock(READ_SIZE)
          # Handle break condition
          if data.include?("*** ERROR: unknown command 'endcommand'") # end of response
            # Get anything that might be before the line but included in this response
            response += data.split("*** ERROR: unknown command 'endcommand'")[0].to_s
            break
          end
          response += data
        rescue IO::WaitReadable
          # Retry when there's more data available
          IO.select([socket])
        rescue EOFError
          break
        end
      end
    rescue => e
      logger.error("Error: #{e.message}")
    ensure
      # Close the socket
      socket.close
    end
    # Sanitize the response
    # Remove startcommand and prior lines
    response = response.split("*** ERROR: unknown command 'startcommand'\r\n")[1].to_s
    # Remove server logs
    response = response.split("\r\n").reject { |l| l[SERVER_LOG_REGEX] }.join("\r\n")
    response
  end
end

if __FILE__ == $0
  client = TelnetClient.new('localhost', 8081)
  response = client.send(ARGV.join(' '))
  puts response
end
