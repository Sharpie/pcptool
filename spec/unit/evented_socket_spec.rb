# -*- encoding: utf-8 -*-
require 'spec_helper'

require 'timeout'

require 'pcptool/evented_socket'

describe Pcptool::EventedSocket do
  describe '#initialize' do
    it 'rejects non-integer port numbers' do
      expect { described_class.new('localhost', '18142') }.to raise_error(ArgumentError, /Port number must be an integer/)
    end
  end

  describe '#connect' do
    include_context('test logging')

    let(:host) { 'localhost' }
    let(:port) { 18142}

    subject { described_class.new(host, port) }

    context 'when establishing a TCP connection' do
      it 'raises Errno::ECONNREFUSED when the server is not listening' do
        expect(test_logger).to receive(:error).with(/ECONNREFUSED raised while connecting to "#{host}:#{port}"/)
        expect { subject.connect }.to raise_error(Errno::ECONNREFUSED)
      end

      context 'when the server hostname cannot be resolved' do
        let(:host) { 'testname.invalid' }

        it 'raises a RuntimeError' do
          expect(test_logger).to receive(:error).with(/Could not resolve the hostname "#{host}" to an IP address/)
          expect { subject.connect }.to raise_error(SocketError)
        end
      end

      context 'when connections are not accepted' do
        let(:timeout) { 1 }

        # RFC 5737 non-routable IP address.
        let(:host) { '192.0.2.1' }

        it 'times out when connecting' do
          expect(test_logger).to receive(:error).with(/Connection attempt to "#{host}:#{port}" timed out after #{timeout} seconds/)

          expect{ Timeout.timeout(5){ subject.connect(timeout: timeout) }}.to raise_error(Errno::ETIMEDOUT)
        end
      end
    end

    context 'when establishing a TLS connection' do
      include_context('TLS Context',
                      name: :client_ssl,
                      ca: 'ca-01',
                      certname: 'pcptool.test',
                      verify_mode: OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT)
      subject { described_class.new(host, port, ssl: client_ssl) }

      context "and the server doesn't support TLS" do
        include_context('TCP Server')
        let(:tcp_accept_handler) do
          lambda do |socket|
            socket.write("HTTP/1.1 400 Bad Request\r\n")
            socket.flush

            socket.close
          end
        end

        it 'fails to connect' do
          expect(test_logger).to receive(:error).with(/SSL_connect .* unknown protocol/)
          expect { subject.connect }.to raise_error(OpenSSL::SSL::SSLError)
        end
      end

      context "and the server's cert is signed by a different CA" do
        include_context('TLS Server', ca: 'ca-02', certname: 'pcp-broker.test')

        it 'fails to connect' do
          expect(test_logger).to receive(:error).with(/SSL_connect .* certificate verify failed/)
          expect { subject.connect }.to raise_error(OpenSSL::SSL::SSLError)
        end
      end

      context "and the server's cert is revoked" do
        include_context('TLS Server', ca: 'ca-01', certname: 'pcp-broker-revoked.test')

        it 'fails to connect' do
          expect(test_logger).to receive(:error).with(/SSL_connect .* certificate verify failed/)
          expect { subject.connect }.to raise_error(OpenSSL::SSL::SSLError)
        end
      end

      context "and the server's cert does not match the hostname" do
        include_context('TLS Server', ca: 'ca-01', certname: 'pcp-broker-noaltname.test')

        it 'fails to connect' do
          expect(test_logger).to receive(:error).with(/hostname "#{host}" does not match the server certificate/)
          expect { subject.connect }.to raise_error(OpenSSL::SSL::SSLError)
        end
      end
    end
  end
end
