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

      attr_reader :connection, :channel, :exchange, :queues, :consumers, :dlq, :circuits, :metrics, :health

      def initialize(serializer:, **options)
        super(serializer: serializer, **options)
        @queues = {}
        @consumers = {}
        @shutdown = false
        @circuits = {}
        @dlq = nil

        # Initialize monitoring
        @metrics = Metrics.new
        @health = nil # Initialized after configure

        # Initialize circuit breakers
        initialize_circuits
      end

      def configure
        connect_to_rabbitmq
        setup_exchange
        setup_dead_letter_queue

        # Initialize health checker after connection is established
        @health = Health.new(self)

        logger.info { "[RabbitMQ] Transport configured with exchange: #{@options[:exchange_name]}" }
      end

      def default_options
        DEFAULT_CONFIG
      end

      def do_publish(message_class, serialized_message, routing_key, routing_options = {})
        start_time = Time.now

        # Use circuit breaker for publishing
        @circuits[:publish].call do
          logger.info { "[RabbitMQ] Publishing #{message_class} (#{serialized_message.bytesize} bytes) with routing key: #{routing_key}" }
          logger.debug { "[RabbitMQ] Message content: #{serialized_message}" }

          # Extract routing components for headers (backward compatibility)
          routing_parts = routing_key.split('.')
          to_recipient = routing_parts[-2] if routing_parts.length >= 3
          from_sender = routing_parts[-1] if routing_parts.length >= 3

          @exchange.publish(
            serialized_message,
            routing_key: routing_key,
            persistent: true,
            timestamp: Time.now.to_i,
            content_type: 'application/json',
            headers: {
              message_class: message_class.to_s,
              smart_message_version: SmartMessage::VERSION,
              from: from_sender,
              to: to_recipient,
              routing_key: routing_key
            }
          )

          # Record successful publish with latency
          latency_ms = ((Time.now - start_time) * 1000).round(2)
          @metrics.record_publish(latency_ms)

          logger.info { "[RabbitMQ] Successfully published #{message_class} to #{to_recipient} from #{from_sender}" }
        end
      rescue CircuitBreaker::CircuitOpenError => e
        @metrics.record_failure(:publish)
        logger.error { "[RabbitMQ] Circuit breaker open, cannot publish: #{e.message}" }
        raise Error, "Publishing circuit breaker is open"
      rescue => e
        logger.error { "[RabbitMQ] Publish failed: #{e.message}" }
        raise
      end

      # Override subscribe to add RabbitMQ-specific queue and consumer setup
      def subscribe(message_classes, handler = nil, options = {}, &block)
        # Call parent method first to register with dispatcher
        super(message_classes, handler, options, &block)
        
        # Now resolve classes and setup RabbitMQ-specific infrastructure
        resolved_classes = resolve_message_classes(message_classes)
        resolved_classes.each do |message_class|
          routing_key = derive_routing_key(message_class.to_s)
          queue_name = derive_queue_name(message_class.to_s)
          setup_queue_and_consumer(queue_name, routing_key, message_class.to_s)
        end
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
            
            # Process the message 
            logger.info { "[RabbitMQ] Pattern received #{message_class} (#{payload.bytesize} bytes) with routing key: #{delivery_info.routing_key}" }
            logger.info { "[RabbitMQ] Message content: #{payload}" }
            
# Simulate message processing for demo purposes
            begin
              # Parse the message data
              parsed_data = JSON.parse(payload)
              payload_data = parsed_data['_sm_payload'] || parsed_data
              
              # Simple processing simulation based on message class
              puts "Processing #{message_class}..."
              case message_class
              when 'OrderMessage'
                puts "Processing order #{payload_data['order_id']} for customer #{payload_data['customer_id']}: $#{payload_data['amount']}"
              when 'AlertMessage'
                puts "ALERT: #{payload_data['severity']} - #{payload_data['message']} from #{payload_data['service']}"
              when 'SystemMessage'
                puts "System #{payload_data['type']}: #{payload_data['data']}"
              else
                puts "Processing #{message_class} with data: #{payload_data}"
              end
              logger.info { "[RabbitMQ] Processed #{message_class} successfully" }
            rescue => processing_error
              logger.error { "[RabbitMQ] Error processing message: #{processing_error.message}" }
            end
            
            # Also try to route through dispatcher if we have a handler
            if @dispatcher.subscribers[message_class]
              receive(message_class, payload)
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

      # Get circuit breaker statistics
      def circuit_stats
        @circuits.transform_values(&:stats)
      end

      # Reset circuit breakers
      def reset_circuits!(name = nil)
        if name
          @circuits[name]&.reset!
          logger.info { "[RabbitMQ] Reset circuit: #{name}" }
        else
          @circuits.each_value(&:reset!)
          logger.info { "[RabbitMQ] Reset all circuits" }
        end
      end

      # Get DLQ statistics
      def dlq_stats
        @dlq&.stats || { message_count: 0 }
      end

      # Inspect DLQ messages
      def dlq_inspect(limit: 10)
        @dlq&.inspect_messages(limit: limit) || []
      end

      # Purge DLQ
      def dlq_purge!
        @dlq&.purge!
      end

      private

      # Initialize circuit breakers
      def initialize_circuits
        state_change_callback = proc { |old_state, new_state| @metrics.record_circuit_state_change }

        @circuits[:publish] = CircuitBreaker.new(
          :publish,
          failure_threshold: @options[:publish_circuit_threshold] || 5,
          timeout: @options[:publish_circuit_timeout] || 60,
          reset_timeout: @options[:publish_circuit_reset] || 30,
          on_state_change: state_change_callback
        )

        @circuits[:consume] = CircuitBreaker.new(
          :consume,
          failure_threshold: @options[:consume_circuit_threshold] || 10,
          timeout: @options[:consume_circuit_timeout] || 120,
          reset_timeout: @options[:consume_circuit_reset] || 60,
          on_state_change: state_change_callback
        )
      end

      # Setup dead letter queue
      def setup_dead_letter_queue
        return if @options[:disable_dlq]

        @dlq = DeadLetterQueue.new(
          @channel,
          @options[:exchange_name],
          durable: @options[:queue_durable],
          ttl: @options[:dlq_ttl]
        )

        logger.debug { "[RabbitMQ] Dead Letter Queue enabled" }
      rescue => e
        logger.error { "[RabbitMQ] Failed to setup DLQ: #{e.message}" }
        @dlq = nil
      end

      # Override to use RabbitMQ-native dispatcher that leverages topic routing
      def create_dispatcher
        RabbitMQDispatcher.new
      end

      # Build standard 3-component routing key: {message_class}.{to}.{from}
      # @param message [Object] Message instance
      # @param routing_options [Hash] Routing options with :to and :from keys
      # @return [String] Formatted routing key
      def build_standard_routing_key(message, routing_options = {})
        message_class = message.class.to_s
        to = sanitize_routing_component(routing_options[:to] || 'broadcast')
        from = sanitize_routing_component(routing_options[:from] || 'anonymous')

        "#{message_class}.#{to}.#{from}"
      end

      # Sanitize a routing key component by replacing invalid characters
      # @param value [String, Symbol] Component to sanitize
      # @return [String] Sanitized component
      def sanitize_routing_component(value)
        value.to_s.gsub(/[^a-zA-Z0-9_\-]/, '_')
      end

      # Resolve message classes from various input types
      # @param message_classes [Class, Array<Class>, String, Symbol, Regexp] Input to resolve
      # @return [Array<Class>] Array of message classes
      def resolve_message_classes(message_classes)
        case message_classes
        when Class
          [message_classes]
        when Array
          message_classes.flat_map { |mc| resolve_message_classes(mc) }
        when String, Symbol
          # Convert string/symbol to class constant
          [Object.const_get(message_classes.to_s)]
        when Regexp
          # Find all SmartMessage descendants matching the pattern
          SmartMessage::Base.descendants.select do |klass|
            klass.name =~ message_classes
          end
        else
          raise ArgumentError, "Invalid message_classes type: #{message_classes.class}"
        end
      end

      # Resolve handler from various input types
      # @param handler [Proc, Method, String, nil] Handler to resolve
      # @param block [Proc, nil] Block handler
      # @param message_classes [Array<Class>] Message classes being subscribed
      # @return [Proc] Resolved handler
      def resolve_handler(handler, block, message_classes)
        # Block takes precedence
        return block if block

        # Use provided handler
        return handler if handler.is_a?(Proc) || handler.is_a?(Method)

        # String handler format: "ClassName.method_name"
        return handler if handler.is_a?(String)

        # No handler provided, try to use default process method
        if message_classes.length == 1 && message_classes.first.method_defined?(:process)
          proc { |msg| msg.process }
        else
          raise ArgumentError, "No handler provided and message class(es) don't define :process method"
        end
      end

      # Remove all handlers for a message class (public method)
      # @param message_class [String, Class] Message class to unsubscribe
      public def unsubscribe!(message_class)
        message_class_str = message_class.to_s

        # Remove from dispatcher
        @dispatcher.drop_all(message_class_str)

        # Stop and remove consumer
        queue_name = derive_queue_name(message_class_str)
        stop_consumer(queue_name)

        logger.info { "[RabbitMQ] Unsubscribed all handlers for #{message_class_str}" }
      end

      def connect_to_rabbitmq
        connection_options = {
          host: @options[:host],
          port: @options[:port],
          username: @options[:username],
          password: @options[:password],
          vhost: @options[:vhost],
          heartbeat: @options[:heartbeat],
          connection_timeout: @options[:connection_timeout],
          automatically_recover: true,
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
        # Bunny handles recovery automatically with the recovery_attempts option
        # No manual recovery setup needed in current versions
        logger.debug { "[RabbitMQ] Automatic recovery enabled" }
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
          start_time = Time.now

          begin
            # Validate message headers
            if properties&.headers&.[]('message_class') == message_class.to_s
              logger.info { "[RabbitMQ] Received #{message_class} (#{payload.bytesize} bytes) with routing key: #{delivery_info.routing_key}" }
              logger.debug { "[RabbitMQ] Message content: #{payload}" }

              # Process with circuit breaker
              @circuits[:consume].call do
                receive(message_class.to_s, payload)
              end

              # Record successful receive with latency
              latency_ms = ((Time.now - start_time) * 1000).round(2)
              @metrics.record_receive(latency_ms)

              @channel.ack(delivery_info.delivery_tag)
            else
              logger.warn { "[RabbitMQ] Message class mismatch, rejecting message" }
              @channel.reject(delivery_info.delivery_tag, false)
            end
          rescue CircuitBreaker::CircuitOpenError => e
            @metrics.record_failure(:subscribe)
            logger.error { "[RabbitMQ] Consumer circuit breaker open: #{e.message}" }
            # Requeue message for later retry
            @channel.reject(delivery_info.delivery_tag, true)
          rescue => e
            @metrics.record_failure(:subscribe)
            logger.error { "[RabbitMQ] Error processing message: #{e.message}" }
            logger.error { "[RabbitMQ] Backtrace: #{e.backtrace.first(3).join("\n")}" }

            # Send to DLQ if available
            if @dlq
              @metrics.record_dlq_message
              @dlq.send_to_dlq(
                message_class,
                payload,
                delivery_info.routing_key,
                e,
                { delivery_tag: delivery_info.delivery_tag }
              )
            end

            # Reject without requeue (already in DLQ)
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
    
    # RabbitMQ-native dispatcher that leverages topic exchange routing
    # This optimizes message routing by using RabbitMQ's built-in pattern matching
    class RabbitMQDispatcher
      attr_reader :subscribers
      
      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @routing_keys = Hash.new { |h, k| h[k] = [] }
      end
      
      # Add a handler for a message class with routing key patterns
      def add(message_class, handler, options = {})
        handler_info = {
          handler: handler,
          options: options,
          routing_patterns: build_routing_patterns(message_class, options)
        }
        
        @subscribers[message_class] << handler_info
        
        # Store routing patterns for efficient lookup
        handler_info[:routing_patterns].each do |pattern|
          @routing_keys[pattern] << handler_info
        end
      end
      
      # Remove a specific handler
      def drop(message_class, handler_id)
        removed = @subscribers[message_class].reject! do |handler_info|
          handler_info[:handler] == handler_id
        end
        
        # Clean up routing keys
        if removed
          @routing_keys.each do |pattern, handlers|
            handlers.reject! { |h| removed.include?(h) }
          end
        end
      end
      
      # Remove all handlers for a message class
      def drop_all(message_class)
        removed = @subscribers.delete(message_class) || []
        
        # Clean up routing keys
        @routing_keys.each do |pattern, handlers|
          handlers.reject! { |h| removed.include?(h) }
        end
      end
      
      # Route message to appropriate handlers using routing key
      def route(message, routing_key = nil)
        message_class = message.class.to_s
        
        # Find handlers for this message class
        handlers = @subscribers[message_class] || []
        
        # Execute each handler
        handlers.each do |handler_info|
          begin
            # Check if routing key matches any of the handler's patterns
            if routing_key_matches?(routing_key, handler_info[:routing_patterns])
              execute_handler(handler_info[:handler], message)
            end
          rescue => e
            logger.error { "[RabbitMQDispatcher] Error executing handler: #{e.message}" }
          end
        end
      end
      
      private
      
      def logger
        @logger ||= SmartMessage::Logger.default
      end
      
      # Build routing key patterns for a message class and options
      def build_routing_patterns(message_class, options)
        base_pattern = message_class.gsub('::', '.')
        
        # Extract routing filters
        to_filters = Array(options[:to] || '*')
        from_filters = Array(options[:from] || '*')
        
        patterns = []
        to_filters.each do |to|
          from_filters.each do |from|
            patterns << "#{base_pattern}.#{to}.#{from}"
          end
        end
        
        patterns
      end
      
      # Check if routing key matches any of the patterns
      def routing_key_matches?(routing_key, patterns)
        return true if routing_key.nil? || patterns.empty?
        
        patterns.any? do |pattern|
          # Convert RabbitMQ wildcard pattern to regex
          regex_pattern = pattern
            .gsub('.', '\.')   # Escape dots
            .gsub('*', '[^.]+') # * matches one word
            .gsub('#', '.*')    # # matches zero or more words
          
          routing_key =~ /^#{regex_pattern}$/
        end
      end
      
      # Execute handler with appropriate signature
      def execute_handler(handler, message)
        case handler
        when Proc, Method
          handler.call(message)
        when String
          # String handler like "MyService.handle_message"
          if handler.include?('.')
            service_name, method_name = handler.split('.', 2)
            service = Object.const_get(service_name)
            service.send(method_name, message)
          else
            raise ArgumentError, "Invalid string handler format: #{handler}"
          end
        else
          raise ArgumentError, "Invalid handler type: #{handler.class}"
        end
      end
    end

  end
end

# Load nested classes after RabbitMQ class is defined
require_relative "rabbitmq/circuit_breaker"
require_relative "rabbitmq/dead_letter_queue"
require_relative "rabbitmq/metrics"
require_relative "rabbitmq/health"
