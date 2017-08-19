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

    subject { described_class.new('localhost', 18142) }

    context 'when establishing a TCP connection' do
      it 'raises Errno::ECONNREFUSED when the server is not listening' do
        expect(test_logger).to receive(:error).with(/ECONNREFUSED raised while connecting to "localhost"/)
        expect { subject.connect }.to raise_error(Errno::ECONNREFUSED)
      end

      it 'raises RuntimeError when the server hostname cannot be resolved' do
        socket = described_class.new('testname.invalid', 18142)

        expect(test_logger).to receive(:error).with(/Could not resolve the hostname "testname\.invalid" to an IP address/)
        expect { socket.connect }.to raise_error(SocketError)
      end

      context 'when connections are not accepted' do
        include_context('TCP server', listen: false)
        let(:timeout) { 1 }

        it 'times out when connecting' do
          expect(test_logger).to receive(:error).with(/Connection attempt to "localhost" timed out after #{timeout} seconds/)

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
      subject { described_class.new('localhost', 18142, ssl: client_ssl) }

      context "and the server doesn't support TLS" do
        include_context('TCP server')

        before(:each) do
          @srv_sock = nil

          @accept_thread = Thread.new do
            begin
              @srv_sock, _ = @server.accept

              @srv_sock.close
            rescue => e
              puts "#{e.class} error in server accept thread: #{e.message}"
            end
          end
        end

        after(:each) do
          @accept_thread.kill
          @accept_thread.join
        end

        it 'fails to connect' do
          expect(test_logger).to receive(:error).with(/SSL_connect .* read server hello/)
          expect { subject.connect }.to raise_error(OpenSSL::SSL::SSLError)
        end
      end

      context "and the server's cert is signed by a different CA" do
        include_context('TLS Server', ca: 'ca-02', certname: 'pcp-broker.test')

        before(:each) do
          @srv_sock = nil

          @accept_thread = Thread.new do
            begin
              @srv_sock, _ = @server.accept

              @srv_sock.close
            rescue => e
              puts "#{e.class} error in server accept thread: #{e.message}"
            end
          end
        end

        after(:each) do
          @accept_thread.kill
          @accept_thread.join
        end

        it 'fails to connect' do
          expect(test_logger).to receive(:error).with(/SSL_connect .* certificate verify failed/)
          expect { subject.connect }.to raise_error(OpenSSL::SSL::SSLError)
        end
      end

      context "and the server's cert is revoked" do
        include_context('TLS Server', ca: 'ca-01', certname: 'pcp-broker-revoked.test')

        before(:each) do
          @srv_sock = nil

          @accept_thread = Thread.new do
            begin
              @srv_sock, _ = @server.accept

              @srv_sock.close
            rescue => e
              puts "#{e.class} error in server accept thread: #{e.message}"
            end
          end
        end

        after(:each) do
          @accept_thread.kill
          @accept_thread.join
        end

        it 'fails to connect' do
          expect(test_logger).to receive(:error).with(/SSL_connect .* certificate verify failed/)
          expect { subject.connect }.to raise_error(OpenSSL::SSL::SSLError)
        end
      end

      context "and the server's cert does not match the hostname" do
        include_context('TLS Server', ca: 'ca-01', certname: 'pcp-broker-noaltname.test')

        before(:each) do
          @srv_sock = nil

          @accept_thread = Thread.new do
            begin
              @srv_sock, _ = @server.accept

              @srv_sock.close
            rescue => e
              puts "#{e.class} error in server accept thread: #{e.message}"
            end
          end
        end

        after(:each) do
          @accept_thread.kill
          @accept_thread.join
        end

        it 'fails to connect' do
          expect(test_logger).to receive(:error).with(/hostname "localhost" does not match the server certificate/)
          expect { subject.connect }.to raise_error(OpenSSL::SSL::SSLError)
        end
      end
    end
  end
end
