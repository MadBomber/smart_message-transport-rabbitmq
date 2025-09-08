# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Mock SmartMessage dependencies for testing
module SmartMessage
  class Logger
    def self.default
      MockLogger.new
    end
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
  
  class RoutingDispatcher
    attr_reader :subscribers
    
    def initialize
      @subscribers = Hash.new { |h, k| h[k] = [] }
    end
    
    def add(message_class, handler, options = {})
      @subscribers[message_class] << { handler: handler, options: options }
    end
    
    def drop(message_class, handler)
      @subscribers[message_class].reject! { |h| h[:handler] == handler }
    end
    
    def drop_all(message_class)
      @subscribers.delete(message_class)
    end
    
    def route(message)
      # Simple routing for testing
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
      MockDeadLetterQueue.new
    end
  end
end

class MockLogger
  def info(&block)
    # Do nothing for tests
  end
  
  def debug(&block)
    # Do nothing for tests
  end
  
  def error(&block)
    # Do nothing for tests
  end
  
  def warn(&block)
    # Do nothing for tests
  end
end

class MockDeadLetterQueue
  def enqueue(*args)
    # Do nothing for tests
  end
end

require "smart_message/transport/rabbitmq"
require "minitest/autorun"
