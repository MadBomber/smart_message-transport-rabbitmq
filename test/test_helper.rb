# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "minitest/reporters"
require "json"
require "ostruct"

# Use progress reporter for better output
Minitest::Reporters.use! [
  Minitest::Reporters::ProgressReporter.new(color: true, detailed_skip: false)
]

# Minimal mock SmartMessage components (only what can't come from real gem)
module SmartMessage
  VERSION = "0.1.0" unless defined?(VERSION)

  class Logger
    def self.default
      @default ||= new
    end

    def info(&block); end
    def debug(&block); end
    def error(&block); end
    def warn(&block); end
  end

  module Errors
    class TransportNotConfigured < StandardError; end
    class SerializerNotConfigured < StandardError; end
    class NotImplemented < StandardError; end
  end

  class Base
    def self.descendants
      []
    end
  end

  class FluentSubscriptionBuilder
    def initialize(transport)
      @transport = transport
    end
  end

  module CircuitBreaker
    DEFAULT_CONFIGS = {
      transport_publish: {
        threshold: { failures: 5, within: 60 },
        reset_after: 30
      },
      transport_subscribe: {
        threshold: { failures: 10, within: 120 },
        reset_after: 60
      }
    }.freeze

    module Fallbacks
      def self.dead_letter_queue
        proc { |error| { sent_to_dlq: true, error: error.message } }
      end
    end
  end

  class DeadLetterQueue
    def self.default
      @default ||= new
    end

    def enqueue(*args); end
  end
end

# Simple serializer for testing
class MockSerializer
  def encode(message)
    JSON.generate({
      _sm_payload: extract_payload(message),
      _sm_header: {}
    })
  end

  def decode(data)
    parsed = JSON.parse(data)
    OpenStruct.new(parsed['_sm_payload'] || parsed)
  end

  private

  def extract_payload(message)
    if message.respond_to?(:to_h)
      message.to_h
    elsif message.respond_to?(:instance_variables)
      message.instance_variables.each_with_object({}) do |var, hash|
        key = var.to_s.delete('@')
        hash[key] = message.instance_variable_get(var)
      end
    else
      { data: message.to_s }
    end
  end
end

# Load support files
require_relative "support/test_helpers"
require_relative "support/test_messages"

# Include test helpers in all tests
class Minitest::Test
  include TestHelpers
end

# Load the main library
require "smart_message/transport/rabbitmq"
