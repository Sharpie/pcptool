# -*- encoding: utf-8 -*-
require 'spec_helper'

require 'pcptool/config'
require 'stringio'

describe Pcptool::Config do
  class TestClass
    extend Forwardable

    instance_delegate([:logger] => :@config)

    def initialize(config: Pcptool::Config.config)
      @config = config
    end
  end

  describe '#initialize' do
    context 'when configured with defaults' do
      subject { TestClass.new }

      [:unknown, :fatal, :error, :warn, :info, :debug].each do |method|
        it "accepts logs at #{method} level, but doesn't write anything" do
          expect_any_instance_of(Logger::LogDevice).to receive(:write).never

          subject.logger.send(method, "test log at #{method} level")
        end
      end
    end

    context 'when configured with an output device for logs' do
      let(:output) { StringIO.new }
      let(:logger) do
        logger = Logger.new(output)
        logger.level = Logger::DEBUG
        logger
      end
      let(:config) { Pcptool::Config::Settings.new(logger: logger) }

      subject { TestClass.new(config: config) }

      [:unknown, :fatal, :error, :warn, :info, :debug].each do |method|
        it "accepts logs at #{method} level" do
          log_line = "test log at #{method} level"

          subject.logger.send(method, log_line)

          expect(output.string).to include(log_line)
        end
      end
    end
  end
end
