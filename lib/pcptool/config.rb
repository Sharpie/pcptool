# -*- encoding: utf-8 -*-
require 'forwardable'

require 'pcptool'

# Stores and sets global configuration
#
# This module stores a global instance of {Pcptool::Config::Settings}.
#
# @api public
# @since 0.0.1
module Pcptool::Config
  require_relative 'config/settings'

  # Return global configuration
  #
  # @return [Pcptool::Config::Settings]
  def self.config
    @settings ||= Pcptool::Config::Settings.new
  end
end
