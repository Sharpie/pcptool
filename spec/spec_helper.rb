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

RSpec.shared_context('TCP server') do |host: 'localhost', port: 18142|
  # Sets up a TCP server bound to the given socket before each example and
  # then tears it down afterwards.
  before(:each) do
    addrinfo = Socket.getaddrinfo(host, nil)
    address = Socket.pack_sockaddr_in(port, addrinfo[0][3])

    @server = Socket.new(Socket.const_get(addrinfo[0][0]), :STREAM)
    # Enable address re-use so that multiple tests of bad behavior can be run
    # using the same port without dangling TIME_WAIT sockets causing bind()
    # to fail.
    @server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    @server.bind(address)

    # Established connections can be retrieved by calling @server.accept
    # inside of a test.
    @server.listen(128)
  end

  after(:each) do
    begin
      @server.close
    rescue IOError
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
  # Sets up a TLS server bound to the given port before each example and then
  # tears it down afterwards.
  include_context('TLS Context', name: :server_ssl, ca: ca, certname: certname)

  before(:each) do
    addrinfo = Socket.getaddrinfo(host, nil)
    address = Socket.pack_sockaddr_in(port, addrinfo[0][3])

    @tcp_server = Socket.new(Socket.const_get(addrinfo[0][0]), :STREAM)
    # Enable address re-use so that multiple tests of bad behavior can be run
    # using the same port without dangling TIME_WAIT sockets causing bind()
    # to fail.
    @tcp_server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    @tcp_server.bind(address)

    @server = OpenSSL::SSL::SSLServer.new(@tcp_server, server_ssl)

    # Established connections can be retrieved by calling @server.accept
    # inside of a test.
    @server.listen(128)
  end

  after(:each) do
    begin
      @server.close
    rescue IOError
      # Already closed.
    end
  end
end
