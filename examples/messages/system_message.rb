# frozen_string_literal: true

require 'smart_message'

class SystemMessage < SmartMessage::Base
  property :type, required: true
  property :data

  def process
    puts "System #{type}: #{data}"
  end
end