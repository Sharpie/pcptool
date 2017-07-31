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

RSpec.shared_context('TCP server') do |host: 'localhost', port: 18142, listen: true|
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
    @server.listen(128) if listen
  end

  after(:each) do
    begin
      @server.close
    rescue IOError
      # Already closed.
    end
  end
end

RSpec.shared_context('TLS Context') do |name:, ca:, certname:|
  let(name) do
    ssl_dir = File.join(FIXTURE_DIRECTORY, 'ssl', ca)

    ssl_context = OpenSSL::SSL::SSLContext.new

    ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(
      File.join(ssl_dir, 'certs', "#{certname}.pem")))
    ssl_context.key = OpenSSL::PKey::RSA.new(File.read(
      File.join(ssl_dir, 'private_keys', "#{certname}.pem")))

    ssl_context
  end
end
