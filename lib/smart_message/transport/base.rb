# frozen_string_literal: true

# Stub Base transport class for development/testing
# In production, this would come from the smart_message gem

module SmartMessage
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
        require_relative '../../routing_dispatcher' if defined?(SmartMessage::RoutingDispatcher)
        SmartMessage::RoutingDispatcher.new
      rescue
        # Fallback for tests
        Object.const_defined?('SmartMessage::RoutingDispatcher') ?
          SmartMessage::RoutingDispatcher.new :
          nil
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
        raise NotImplementedError, "#{self.class} must implement #publish"
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
        # Override in subclass for custom resolution
        case message_classes
        when Class
          [message_classes]
        when Array
          message_classes
        else
          [message_classes]
        end
      end

      def resolve_handler(handler, block, message_classes)
        # Override in subclass for custom handler resolution
        block || handler || proc { |msg| msg }
      end
    end
  end
end
