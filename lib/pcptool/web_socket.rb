# -*- encoding: utf-8 -*-
require 'thread'
require 'observer'

require 'websocket/driver'

require 'pcptool/config'

module Pcptool; end

# A wrapper that joins a socket to a WebSocket::Driver
#
# @api public
# @since 0.0.1
class Pcptool::WebSocket
  include Observable
  extend Forwardable

  instance_delegate([:logger] => :@config)

  attr_reader :url

  def initialize(socket, url, config: Pcptool::Config.config)
    @socket = socket
    @url = url
    @config = config

    @state = :closed
  end

  def connect
    return unless closed?

    @socket.connect

    @driver = WebSocket::Driver.client(self)
    @driver.on(:message) do |msg|
      logger.debug { "WebSocket received: #{msg}" }
      changed
      notify_observers(msg)
    end

    @driver.start

    @state = :open

    start_threads
  end

  def close
    return if closed?

    @driver.close
    @state = :closed
    @socket.close

    sleep 0.1 while [@event_thread].any?(&:alive?)
  end

  def closed?
    @state == :closed
  end

  def write(data)
    @socket.write(data)
  end

  def send_text(data)
    @driver.text(data)
  end

  private

  def start_threads
    @event_thread = Thread.new { event_loop }
  end

  def event_loop
    loop do
      break if closed?

      # NOTE: Blocks on the read queue of the underlying socket. For a true
      # event loop, we'd want to have some sort of break to allow other events
      # to be processed.
      data = @socket.read

      @driver.parse(data) unless data.nil?

      Thread.pass
    end
  rescue => e
    # TODO: Post to an event loop. Mostly here to log unexpected errors.
    logger.error('%{error_class} in WebSocket event loop: %{message}' % {
                 error_class: e.class,
                 message: e.message})

    raise e
  end
end
