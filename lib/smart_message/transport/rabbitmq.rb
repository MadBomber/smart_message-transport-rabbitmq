# frozen_string_literal: true

require_relative "rabbitmq/version"
require 'smart_message/transport/base'
require 'bunny'
require 'json'

module SmartMessage
  module Transport
    class RabbitMQ < Base
      class Error < StandardError; end
      
      DEFAULT_CONFIG = {
        host: ENV['RABBITMQ_HOST'] || 'localhost',
        port: ENV['RABBITMQ_PORT']&.to_i || 5672,
        username: ENV['RABBITMQ_USERNAME'] || 'guest',
        password: ENV['RABBITMQ_PASSWORD'] || 'guest',
        vhost: ENV['RABBITMQ_VHOST'] || '/',
        heartbeat: ENV['RABBITMQ_HEARTBEAT']&.to_i || 30,
        connection_timeout: ENV['RABBITMQ_CONNECTION_TIMEOUT']&.to_i || 5,
        recovery_attempts: ENV['RABBITMQ_RECOVERY_ATTEMPTS']&.to_i || 5,
        recovery_attempts_exhausted: proc { |settings| raise Error, "Failed to recover RabbitMQ connection after #{settings[:recovery_attempts]} attempts" },
        exchange_name: ENV['SMART_MESSAGE_EXCHANGE'] || 'smart_message',
        exchange_type: :topic,
        exchange_durable: true,
        queue_durable: true,
        queue_auto_delete: false,
        prefetch: 10
      }.freeze

      attr_reader :connection, :channel, :exchange, :queues, :consumers

      def initialize(**options)
        super(**options)
        @queues = {}
        @consumers = {}
        @shutdown = false
      end

      def configure
        connect_to_rabbitmq
        setup_exchange
        logger.info { "[RabbitMQ] Transport configured with exchange: #{@options[:exchange_name]}" }
      end

      def default_options
        DEFAULT_CONFIG
      end

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

      def subscribe(message_class, process_method, filter_options = {})
        super(message_class, process_method, filter_options)
        
        routing_key = derive_routing_key(message_class)
        queue_name = derive_queue_name(message_class)
        
        setup_queue_and_consumer(queue_name, routing_key, message_class)
      end

      def unsubscribe(message_class, process_method)
        super(message_class, process_method)
        
        # Only remove consumer if no more subscribers for this message class
        if @dispatcher.subscribers[message_class].empty?
          queue_name = derive_queue_name(message_class)
          stop_consumer(queue_name)
        end
      end

      def connected?
        !@shutdown && @connection&.connected? && @channel&.open?
      end

      def connect
        configure
        logger.info { "[RabbitMQ] Transport connected" }
      end

      def disconnect
        @shutdown = true
        
        # Stop all consumers
        @consumers.values.each(&:cancel)
        @consumers.clear
        
        # Close channel and connection
        @channel&.close
        @connection&.close
        
        logger.info { "[RabbitMQ] Transport disconnected" }
      end

      private

      def connect_to_rabbitmq
        connection_options = {
          host: @options[:host],
          port: @options[:port],
          username: @options[:username],
          password: @options[:password],
          vhost: @options[:vhost],
          heartbeat: @options[:heartbeat],
          connection_timeout: @options[:connection_timeout],
          recovery_attempts: @options[:recovery_attempts],
          recovery_attempts_exhausted: @options[:recovery_attempts_exhausted]
        }

        @connection = Bunny.new(connection_options)
        @connection.start
        @channel = @connection.create_channel
        @channel.prefetch(@options[:prefetch])
        
        setup_connection_recovery
        
        logger.debug { "[RabbitMQ] Connected to #{@options[:host]}:#{@options[:port]}" }
      rescue => e
        logger.error { "[RabbitMQ] Connection failed: #{e.message}" }
        raise Error, "Failed to connect to RabbitMQ: #{e.message}"
      end

      def setup_exchange
        @exchange = @channel.exchange(
          @options[:exchange_name],
          type: @options[:exchange_type],
          durable: @options[:exchange_durable]
        )
        
        logger.debug { "[RabbitMQ] Exchange '#{@options[:exchange_name]}' ready" }
      end

      def setup_connection_recovery
        @connection.on_recovery do |conn|
          logger.info { "[RabbitMQ] Connection recovered" }
          # Re-create channel and exchange after recovery
          @channel = conn.create_channel
          @channel.prefetch(@options[:prefetch])
          setup_exchange
          
          # Restart consumers
          restart_consumers
        end

        @connection.on_recovery_failure do |conn, exception|
          logger.error { "[RabbitMQ] Connection recovery failed: #{exception.message}" }
        end
      end

      def restart_consumers
        @consumers.keys.each do |queue_name|
          queue = @queues[queue_name]
          next unless queue
          
          # Find the message class associated with this queue
          message_class = @dispatcher.subscribers.keys.find do |klass|
            derive_queue_name(klass) == queue_name
          end
          
          if message_class
            routing_key = derive_routing_key(message_class)
            setup_queue_and_consumer(queue_name, routing_key, message_class, restart: true)
          end
        end
      end

      def setup_queue_and_consumer(queue_name, routing_key, message_class, restart: false)
        return if @consumers[queue_name] && !restart
        
        # Stop existing consumer if restarting
        stop_consumer(queue_name) if restart
        
        # Create or get queue
        queue = @channel.queue(
          queue_name,
          durable: @options[:queue_durable],
          auto_delete: @options[:queue_auto_delete]
        )
        
        # Bind queue to exchange with routing key
        queue.bind(@exchange, routing_key: routing_key)
        @queues[queue_name] = queue
        
        # Create consumer
        consumer = queue.subscribe(manual_ack: true, block: false) do |delivery_info, properties, payload|
          begin
            # Validate message headers
            if properties&.headers&.[]('message_class') == message_class.to_s
              receive(message_class.to_s, payload)
              @channel.ack(delivery_info.delivery_tag)
            else
              logger.warn { "[RabbitMQ] Message class mismatch, rejecting message" }
              @channel.reject(delivery_info.delivery_tag, false)
            end
          rescue => e
            logger.error { "[RabbitMQ] Error processing message: #{e.message}" }
            @channel.reject(delivery_info.delivery_tag, false)
          end
        end
        
        @consumers[queue_name] = consumer
        logger.debug { "[RabbitMQ] Consumer started for queue: #{queue_name}" }
      end

      def stop_consumer(queue_name)
        consumer = @consumers.delete(queue_name)
        consumer&.cancel
        @queues.delete(queue_name)
        logger.debug { "[RabbitMQ] Consumer stopped for queue: #{queue_name}" }
      end

      def derive_routing_key(message_class)
        message_class.to_s.gsub('::', '.').downcase
      end

      def derive_queue_name(message_class)
        "smart_message.#{derive_routing_key(message_class)}"
      end

      # Enhanced routing methods with from/to UUID support

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
        @queues[queue_name] = queue
        
        # Create consumer that routes to appropriate message class
        consumer = queue.subscribe(manual_ack: true, block: false) do |delivery_info, properties, payload|
          begin
            # Extract message class from headers or routing key
            message_class = properties.headers['message_class'] || 
                          extract_message_class_from_routing_key(delivery_info.routing_key)
            
            # Process through dispatcher if we have a handler
            if message_class && @dispatcher.subscribers[message_class]
              receive(message_class, payload)
            else
              logger.debug { "[RabbitMQ] No handler for message class: #{message_class}" }
            end
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
      def subscribe_to_recipient(recipient_id)
        pattern = "#.*.#{sanitize_for_routing_key(recipient_id)}"
        subscribe_pattern(pattern, :process, {})
      end
      
      # Subscribe to all messages from a specific sender
      def subscribe_from_sender(sender_id)
        pattern = "#.#{sanitize_for_routing_key(sender_id)}.*"
        subscribe_pattern(pattern, :process, {})
      end
      
      # Subscribe to specific message type regardless of sender/recipient
      def subscribe_to_type(message_type)
        pattern = "*.#{message_type.to_s.gsub('::', '.').downcase}.*.*"
        subscribe_pattern(pattern, :process, {})
      end
      
      # Subscribe to all alerts/emergencies
      def subscribe_to_alerts
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
      def subscribe_to_broadcasts
        pattern = "#.*.broadcast"
        subscribe_pattern(pattern, :process, {})
      end

      # Fluent API support
      def where
        SubscriptionBuilder.new(self)
      end

      private

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

      def subscribe
        pattern = build
        @transport.subscribe_pattern(pattern, :process, {})
      end
    end
  end
end
