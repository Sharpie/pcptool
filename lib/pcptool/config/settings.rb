# -*- encoding: utf-8 -*-
require 'logger'

require 'pcptool'

# Class for top-level Pcptool configuration
#
# Instances of this class hold top-level configuration values and shared
# service objects such as loggers.
#
# @api public
# @since 0.0.1
class Pcptool::Config::Settings
  # Access the logger instance
  #
  # The object stored here should conform to the interface presented by
  # the Ruby logger. Defaults to a Logger instance that has no output device
  # configured.
  #
  # @return [Logger]
  attr_accessor :logger

  def initialize(logger: nil)
    @logger = logger || Logger.new(nil)
  end
end
