# frozen_string_literal: true

# Enhanced RabbitMQ transport with from/to UUID routing capabilities
# This demonstrates how to extend routing keys with sender/recipient information

require_relative "rabbitmq/version"
require 'smart_message/transport/base'
require 'bunny'
require 'json'

module SmartMessage
  module Transport
    class RabbitMQEnhanced < RabbitMQ
      
      # Override the publish method to extract from/to from message
      def do_publish(message_class, serialized_message)
        # Parse the message to extract routing information
        routing_info = extract_routing_info(serialized_message)
        
        # Build enhanced routing key with from/to
        routing_key = build_enhanced_routing_key(message_class, routing_info)
        
        @exchange.publish(
          serialized_message,
          routing_key: routing_key,
          persistent: true,
          timestamp: Time.now.to_i,
          content_type: 'application/json',
          headers: {
            message_class: message_class.to_s,
            smart_message_version: SmartMessage::VERSION,
            from: routing_info[:from],
            to: routing_info[:to]
          }
        )
        
        logger.debug { "[RabbitMQ] Published with enhanced routing key: #{routing_key}" }
      end

      # Enhanced subscription with pattern support
      def subscribe_pattern(pattern, process_method, filter_options = {})
        # Pattern could be like "#.*.my_uuid" or "emergency.#.*.*"
        queue_name = derive_pattern_queue_name(pattern)
        
        # Create queue and bind with pattern
        queue = @channel.queue(
          queue_name,
          durable: @options[:queue_durable],
          auto_delete: @options[:queue_auto_delete]
        )
        
        # Bind with the pattern (RabbitMQ topic exchange supports wildcards)
        queue.bind(@exchange, routing_key: pattern)
        
        # Create consumer that routes to appropriate message class
        consumer = queue.subscribe(manual_ack: true, block: false) do |delivery_info, properties, payload|
          begin
            # Extract message class from headers or routing key
            message_class = properties.headers['message_class'] || 
                          extract_message_class_from_routing_key(delivery_info.routing_key)
            
            # Process through dispatcher
            receive(message_class, payload)
            @channel.ack(delivery_info.delivery_tag)
          rescue => e
            logger.error { "[RabbitMQ] Error processing pattern message: #{e.message}" }
            @channel.reject(delivery_info.delivery_tag, false)
          end
        end
        
        @consumers[queue_name] = consumer
        logger.info { "[RabbitMQ] Subscribed to pattern: #{pattern}" }
      end

      # Convenience methods for common subscription patterns
      
      # Subscribe to all messages sent to a specific recipient
      def subscribe_to_recipient(recipient_id, &block)
        pattern = "#.*.#{recipient_id}"
        subscribe_pattern(pattern, :process, {})
      end
      
      # Subscribe to all messages from a specific sender
      def subscribe_from_sender(sender_id, &block)
        pattern = "#.#{sender_id}.*"
        subscribe_pattern(pattern, :process, {})
      end
      
      # Subscribe to specific message type regardless of sender/recipient
      def subscribe_to_type(message_type, &block)
        pattern = "*.#{message_type.to_s.downcase}.*.*"
        subscribe_pattern(pattern, :process, {})
      end
      
      # Subscribe to all alerts/emergencies
      def subscribe_to_alerts(&block)
        patterns = [
          "emergency.#.*.*",
          "#.alert.*.*",
          "#.alarm.*.*",
          "#.critical.*.*"
        ]
        
        patterns.each do |pattern|
          subscribe_pattern(pattern, :process, {})
        end
      end
      
      # Subscribe to broadcast messages
      def subscribe_to_broadcasts(&block)
        pattern = "#.*.broadcast"
        subscribe_pattern(pattern, :process, {})
      end

      private

      def extract_routing_info(serialized_message)
        begin
          message_data = JSON.parse(serialized_message)
          header = message_data['_sm_header'] || {}
          
          {
            from: sanitize_for_routing_key(header['from'] || 'anonymous'),
            to: sanitize_for_routing_key(header['to'] || 'broadcast')
          }
        rescue JSON::ParserError
          logger.warn { "[RabbitMQ] Could not parse message for routing info, using defaults" }
          { from: 'anonymous', to: 'broadcast' }
        end
      end

      def build_enhanced_routing_key(message_class, routing_info)
        # Format: namespace.message_type.from.to
        base_key = derive_routing_key(message_class)
        "#{base_key}.#{routing_info[:from]}.#{routing_info[:to]}"
      end

      def sanitize_for_routing_key(value)
        # RabbitMQ routing keys can't contain certain characters
        # Replace problematic characters with underscores
        value.to_s.gsub(/[^a-zA-Z0-9_\-]/, '_').downcase
      end

      def derive_pattern_queue_name(pattern)
        # Create a queue name based on the pattern
        # Replace wildcards with descriptive names
        sanitized = pattern.gsub('#', 'all').gsub('*', 'any').gsub('.', '_')
        "smart_message.pattern.#{sanitized}"
      end

      def extract_message_class_from_routing_key(routing_key)
        # Extract the message class from routing key
        # Format: namespace.message_type.from.to
        parts = routing_key.split('.')
        
        # Reconstruct the class name (excluding from/to)
        if parts.length >= 4
          # Remove last two parts (from/to)
          class_parts = parts[0..-3]
          class_parts.map(&:capitalize).join('::')
        else
          # Fallback to the full key as class name
          parts.map(&:capitalize).join('::')
        end
      end
    end

    # Subscription builder for fluent API
    class SubscriptionBuilder
      def initialize(transport)
        @transport = transport
        @conditions = {}
      end

      def from(sender_id)
        @conditions[:from] = sender_id
        self
      end

      def to(recipient_id)
        @conditions[:to] = recipient_id
        self
      end

      def type(message_type)
        @conditions[:type] = message_type
        self
      end

      def namespace(ns)
        @conditions[:namespace] = ns
        self
      end

      def build
        pattern_parts = []
        
        # Build pattern based on conditions
        pattern_parts << (@conditions[:namespace] || '*')
        pattern_parts << (@conditions[:type] || '*')
        pattern_parts << (@conditions[:from] || '*')
        pattern_parts << (@conditions[:to] || '*')
        
        pattern_parts.join('.')
      end

      def subscribe(&block)
        pattern = build
        @transport.subscribe_pattern(pattern, :process, {})
      end
    end

    # Extension to add fluent subscription API
    class RabbitMQEnhanced
      def where
        SubscriptionBuilder.new(self)
      end
    end
  end
end

# Usage examples:
#
# transport = SmartMessage::Transport::RabbitMQEnhanced.new
#
# # Subscribe to all messages for me
# transport.subscribe_to_recipient('my_uuid_123')
#
# # Subscribe to all alerts
# transport.subscribe_to_alerts
#
# # Fluent API for complex patterns
# transport.where
#   .from('service_abc')
#   .to('my_uuid_123')
#   .subscribe
#
# # Subscribe to all orders from any source to me
# transport.where
#   .type('ordermessage')
#   .to('my_uuid_123')
#   .subscribe
#
# # Subscribe to everything in emergency namespace
# transport.subscribe_pattern('emergency.#.*.*', :process, {})