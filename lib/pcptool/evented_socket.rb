# -*- encoding: utf-8 -*-
require 'thread'

require 'socket'
require 'openssl'

require 'pcptool/config'

# A TCP socket with integrated event loops
#
# This class implements a TCP socket with integrated loops for reading and
# writing data. The loops push data onto queues which allows for data arriving
# via asynchronous streams to be produced and consumed by synchronous
# processes.
#
# @api public
# @since 0.0.1
class Pcptool::EventedSocket
  extend Forwardable

  instance_delegate([:logger] => :@config)

  def initialize(hostname, port, ssl: nil, config: Pcptool::Config.config)
    raise ArgumentError, "Port number must be an integer" unless port.is_a?(Integer)
    @hostname = hostname
    @port = port
    @ssl_context = ssl
    @config = config

    @read_queue = Queue.new
    @read_wakeup = IO.pipe
    @write_queue = Queue.new

    @state = :closed
  end

  # Establish a connection to the remote server
  #
  # @raise [Errno::ECONNREFUSED] When the server is not listening.
  # @raise [SocketError] When the server hostname cannot be resolved.
  # @raise [Errno::ETIMEDOUT] When the connection cannot be established within
  #   the given timeout.
  #
  # @return [void]
  def connect(timeout: 30)
    return unless closed?

    addrinfo = begin
                 Socket.getaddrinfo(@hostname, nil)
               rescue SocketError => e
                 logger.error('%{error_class}: Could not resolve the hostname "%{hostname}" to an IP address' % {
                   error_class: e.class,
                   hostname: @hostname})

                 raise e
               end

    address = Socket.pack_sockaddr_in(@port, addrinfo[0][3])

    tcp_socket = Socket.new(Socket.const_get(addrinfo[0][0]), :STREAM)
    tcp_socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)

    connect_with_timeout!(tcp_socket, timeout, address)

    @socket = if @ssl_context.nil?
                tcp_socket
              else
                ssl = OpenSSL::SSL::SSLSocket.new(tcp_socket, @ssl_context)
                ssl.hostname = @hostname

                connect_with_timeout!(ssl, timeout)

                unless ssl.context.verify_mode == OpenSSL::SSL::VERIFY_NONE
                  begin
                    ssl.post_connection_check(@hostname)
                  rescue OpenSSL::SSL::SSLError => e
                    logger.error('%{error_class} raised while connecting to "%{hostname}": %{message}' % {
                      error_class: e.class,
                      message: e.message,
                      hostname: @hostname})

                    raise e
                  end
                end

                ssl
              end

    # At this point, the underlying TCP and SSL connections have been
    # established.
    @state = :open

    start_threads
  end

  def closed?
    @state == :closed
  end

  def close
    return if closed?

    @state = :closed
    # Wake up writer thread so that it sees state == :closed and exits.
    @write_queue.push(nil)
    # Wake up reader thread if it happens to be sleeping in IO.select.
    @read_wakeup.last.puts(nil)

    # FIXME: Resort to rude things like Thread.kill if these don't exit within
    # a reasonable timeout.
    sleep 0.1 while [@read_thread, @write_thread].any?(&:alive?)

    # Wake up any thread that may be waiting on us to read data.
    @read_queue.push(nil)

    @socket.close

    #@read_queue.clear
    @write_queue.clear
    @read_wakeup.first.read_nonblock(1024) rescue nil
  end

  def read
    @read_queue.pop
  end

  def write(data)
    @write_queue.push(data)
  end

  private

  def connect_with_timeout!(socket, timeout, address = nil)
    # Address is nil when connecting a TLS socket.
    connect_args = [address].compact

    unless timeout > 0
      socket.connect(*connect_args)
      return
    end

    timeout_error = 'Connection attempt to "%{hostname}" timed out after %{timeout} seconds' % {
      hostname: @hostname,
      timeout: timeout}

    begin
      socket.connect_nonblock(*connect_args)
    rescue IO::WaitWritable
      unless IO.select(nil, [socket], nil, timeout)
        logger.error(timeout_error)
        raise Errno::ETIMEDOUT
      end

      retry
    rescue IO::WaitReadable
      unless IO.select([socket], nil, nil, timeout)
        logger.error(timeout_error)
        raise Errno::ETIMEDOUT
      end

      retry
    rescue Errno::EISCONN
      # All good! We're connected!
    rescue => e
      # Ensure any partially connected socket is cleaned up.
      begin
        socket.close
      rescue IOError
        # Already closed.
      end

      logger.error('%{error_class} raised while connecting to "%{hostname}": %{message}' % {
        error_class: e.class,
        message: e.message,
        hostname: @hostname})

      raise e
    end
  end

  def start_threads
    @read_thread = Thread.new { read_loop }
    @write_thread = Thread.new { write_loop }
  end

  def read_loop
    loop do
      break if closed? || @socket.nil? || @socket.closed?

      data = begin
               @socket.read_nonblock(16_384)
             rescue IO::WaitReadable
               nil
               # NOTE: Also rescue WaitWritable due to SSL re-negotiation.
             end # FIXME: Error handling!

      puts "Received: #{data}" unless data.nil?
      @read_queue.push(data) unless data.nil?

      # Thread sleeps here until data comes in on the socket or something
      # is written to the wakeup pipe.
      IO.select([@socket, @read_wakeup.first], nil, nil, nil)
    end
  rescue => e
    # TODO: Post to an event loop. Mostly here to log unexpected errors.
    logger.error('%{error_class} in read loop: %{message}' % {
                 error_class: e.class,
                 message: e.message})
    raise e
  end

  def write_loop
    loop do
      break if closed? || @socket.nil? || @socket.closed?

      # NOTE: Thread sleeps indefinitely here. To wake it up without sending
      # any data, push a nil onto the write queue.
      data = @write_queue.pop

      unless data.nil?
        puts "Sent: #{data}" unless data.nil?
        written = begin
                    @socket.write_nonblock(data)
                  # NOTE: Also rescue WaitReadable due to SSL re-negotiation.
                  rescue ::IO::WaitWritable
                    retry if ::IO.select(nil, [@socket], nil, 0.1)
                  end # FIXME: Trigger an error if we fail to send data.
      end

      Thread.pass
    end
  rescue => e
    # TODO: Post to an event loop. Mostly here to log unexpected errors.
    logger.error('%{error_class} in write loop: %{message}' % {
                 error_class: e.class,
                 message: e.message})
    raise e
  end
end
