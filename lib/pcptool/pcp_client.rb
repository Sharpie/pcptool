# -*- encoding: utf-8 -*-
require 'thread'
require 'json'

require 'pcptool/message'

require 'pcptool/evented_socket'
require 'pcptool/web_socket'

# A client interface to the Puppet Communications Protocol
#
# @api public
# @since 0.0.1
class Pcptool::PcpClient
  attr_reader :id

  def initialize(server:, client_type: 'pcptool', port: 8142, ssl:)
    uri = URI.parse("wss://#{server}:#{port}/pcp2/#{client_type}")

    @socket = Pcptool::EventedSocket.new(server, port, ssl: ssl)
    @web_socket = Pcptool::WebSocket.new(@socket, uri.to_s)
    @web_socket.add_observer(self)

    subject = ssl.cert.subject.to_s.split('=').last
    @id = URI.parse("pcp://#{subject}/#{client_type}")

    @mailbox = Queue.new
  end

  def connect
    @web_socket.connect
  end

  def close
    @web_socket.close
  end

  def message(**options)
    Pcptool::Message.new(sender: self.id, **options)
  end

  def send_message(**options)
    msg = message(**options)

    write(msg.to_json)
  end

  def receive
    payload = @mailbox.pop

    # TODO: Handle cases where something that isn't JSON is received.
    message = JSON.parse(payload.data, symbolize_names: true)

    Pcptool::Message.new(**message)
  end

  def write(data)
    @web_socket.send_text(data)
  end

  def update(msg)
    @mailbox.push(msg)
  end
end
