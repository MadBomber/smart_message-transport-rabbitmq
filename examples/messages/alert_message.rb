# frozen_string_literal: true

require 'smart_message'

class AlertMessage < SmartMessage::Base
  property :severity, required: true
  property :message, required: true
  property :service, required: true

  def process
    puts "ALERT [#{severity}] from #{service}: #{message}"
  end
end