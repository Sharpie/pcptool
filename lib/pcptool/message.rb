# -*- encoding: utf-8 -*-
require 'securerandom'
require 'json'

# Representation of a PCP message
#
# @see https://github.com/puppetlabs/pcp-specifications/blob/master/pcp/versions/2.0/message.md
#
# @api public
# @since 0.0.1
class Pcptool::Message
  attr_reader :id
  attr_reader :message_type
  attr_reader :sender
  attr_reader :in_reply_to
  attr_reader :data

  def initialize(id: nil, message_type:, target: nil, sender: nil, in_reply_to: nil, data: nil)
    @id = id || SecureRandom.uuid
    @message_type = message_type
    @target = target
    @sender = sender
    @in_reply_to = in_reply_to
    @data = data
  end

  def to_hash
    hash = {
      id: @id,
      message_type: @message_type,
      target: @target,
      sender: @sender,
      in_reply_to: @in_reply_to,
      data: @data
    }

    hash.reject {|_, v| v.nil?}
  end

  def to_json(*args)
    to_hash.to_json(*args)
  end
end
