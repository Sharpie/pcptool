# -*- encoding: utf-8 -*-
require 'rspec'

require 'socket'
require 'openssl'

require 'pcptool/config'

FIXTURE_DIRECTORY = File.expand_path(File.join(__FILE__, '..', 'fixtures'))

RSpec.shared_context('test logging') do
  # A mocked logger that can be used to set expectations.
  let(:test_logger) { instance_double('Logger') }

  before(:each) do
    allow(Pcptool::Config.config).to receive(:logger).and_return(test_logger)
  end
end

RSpec.shared_context('TCP Server') do |host: 'localhost', port: 18142|
  # Sets up a TCP server bound to the given socket before each example and
  # then tears it down afterwards. The :tcp_accept_handler can be overriden
  # to provide a different callback for handling incoming connections.
  let(:tcp_accept_handler) { lambda {|socket| socket.close} }

  before(:each) do
    addrinfo = Socket.getaddrinfo(host, nil)
    address = Socket.pack_sockaddr_in(port, addrinfo[0][3])

    @tcp_server = Socket.new(Socket.const_get(addrinfo[0][0]), :STREAM)
    # Enable address re-use so that multiple tests of bad behavior can be run
    # using the same port without dangling TIME_WAIT sockets causing bind()
    # to fail.
    @tcp_server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    @tcp_server.bind(address)

    # Established connections can be retrieved by calling @server.accept
    # inside of a test.
    @tcp_server.listen(128)

    @tcp_sock = nil

    @tcp_accept_thread = Thread.new do
      begin
        @tcp_sock, _ = @tcp_server.accept

        tcp_accept_handler.call(@tcp_sock)
      rescue => e
        puts "#{e.class} error in TCP server accept thread: #{e.message}"
      end
    end
  end

  after(:each) do
    @tcp_accept_thread.kill
    @tcp_accept_thread.join

    begin
      @tcp_server.close
      @tcp_srv_sock.close
    rescue
      # Already closed.
    end
  end
end

RSpec.shared_context('TLS Context') do |name:, ca:, certname:, verify_mode: OpenSSL::SSL::VERIFY_NONE|
  let(name) do
    ssl_dir = File.join(FIXTURE_DIRECTORY, 'ssl', ca)

    ssl_store = OpenSSL::X509::Store.new

    ssl_store.add_cert OpenSSL::X509::Certificate.new(File.read(
      File.join(ssl_dir, 'ca', 'ca_crt.pem')))
    ssl_store.add_crl OpenSSL::X509::CRL.new(File.read(
      File.join(ssl_dir, 'ca', 'ca_crl.pem')))
    ssl_store.flags= OpenSSL::X509::V_FLAG_CRL_CHECK_ALL|OpenSSL::X509::V_FLAG_CRL_CHECK

    ssl_context = OpenSSL::SSL::SSLContext.new

    ssl_context.cert_store = ssl_store
    ssl_context.verify_mode = verify_mode
    ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(
      File.join(ssl_dir, 'certs', "#{certname}.pem")))
    ssl_context.key = OpenSSL::PKey::RSA.new(File.read(
      File.join(ssl_dir, 'private_keys', "#{certname}.pem")))

    ssl_context
  end
end

RSpec.shared_context('TLS Server') do |ca:, certname:, host: 'localhost', port: 18142|
  # Sets up a TLS server bound to the given socket before each example and
  # then tears it down afterwards. The :tls_accept_handler can be overriden
  # to provide a different callback for handling incoming connections.
  include_context('TLS Context', name: :server_ssl, ca: ca, certname: certname)

  let(:tls_accept_handler) { lambda {|socket| socket.close} }

  before(:each) do
    addrinfo = Socket.getaddrinfo(host, nil)
    address = Socket.pack_sockaddr_in(port, addrinfo[0][3])

    tcp_server = Socket.new(Socket.const_get(addrinfo[0][0]), :STREAM)
    # Enable address re-use so that multiple tests of bad behavior can be run
    # using the same port without dangling TIME_WAIT sockets causing bind()
    # to fail.
    tcp_server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    tcp_server.bind(address)

    @tls_server = OpenSSL::SSL::SSLServer.new(tcp_server, server_ssl)

    # Established connections can be retrieved by calling @server.accept
    # inside of a test.
    @tls_server.listen(128)

    @tls_sock = nil

    @tls_accept_thread = Thread.new do
      begin
        @tls_sock, _ = @tls_server.accept

        tls_accept_handler.call(@tls_sock)
      rescue => e
        puts "#{e.class} error in TLS server accept thread: #{e.message}"
      end
    end
  end

  after(:each) do
    @tls_accept_thread.kill
    @tls_accept_thread.join

    begin
      @tls_server.close
      @tls_srv_sock.close
    rescue
      # Already closed.
    end
  end
end
