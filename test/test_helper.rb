# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "minitest/reporters"

# Use progress reporter for better output
Minitest::Reporters.use! [
  Minitest::Reporters::ProgressReporter.new(color: true, detailed_skip: false)
]

# Mock SmartMessage dependencies for testing
module SmartMessage
  VERSION = "0.1.0" unless defined?(VERSION)

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

  module Transport
    class Base
      attr_reader :serializer, :dispatcher, :options

      def initialize(serializer:, **options)
        @serializer = serializer
        @options = merge_options(options)
        @dispatcher = create_dispatcher
      end

      def default_options
        {}
      end

      def merge_options(options)
        default_options.merge(options)
      end

      def create_dispatcher
        RoutingDispatcher.new
      end

      def logger
        SmartMessage::Logger.default
      end

      # Stub methods that subclasses should implement
      def configure
        # Override in subclass
      end

      def connect
        # Override in subclass
      end

      def disconnect
        # Override in subclass
      end

      def connected?
        false
      end

      def publish(message, **options)
        # Override in subclass
      end

      def subscribe(message_classes, handler = nil, options = {}, &block)
        resolved_classes = resolve_message_classes(message_classes)
        resolved_handler = resolve_handler(handler, block, resolved_classes)

        resolved_classes.each do |message_class|
          @dispatcher.add(message_class.to_s, resolved_handler, options)
        end
      end

      def unsubscribe(message_class, handler)
        @dispatcher.drop(message_class.to_s, handler)
      end

      def receive(message_class, payload)
        message = @serializer.decode(payload)
        @dispatcher.route(message, nil)
      end

      protected

      def resolve_message_classes(message_classes)
        # Override in subclass
        []
      end

      def resolve_handler(handler, block, message_classes)
        # Override in subclass
        block || handler
      end
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

class MockSerializer
  def encode(message)
    JSON.generate({
      _sm_payload: { data: message.respond_to?(:data) ? message.data : "encoded_data" },
      _sm_header: {}
    })
  end

  def decode(data)
    parsed = JSON.parse(data)
    OpenStruct.new(parsed['_sm_payload'] || parsed)
  end
end

# Load support files
require_relative "support/mock_rabbitmq"
require_relative "support/test_helpers"
require_relative "support/test_messages"

# Include test helpers in all tests
class Minitest::Test
  include TestHelpers
end

# Load the main library
require "smart_message/transport/rabbitmq"
