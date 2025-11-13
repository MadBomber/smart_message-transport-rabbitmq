# frozen_string_literal: true

# Mock RabbitMQ components for testing without requiring a real RabbitMQ server

module MockRabbitMQ
  class MockConnection
    attr_reader :connected, :channels, :options

    def initialize(options = {})
      @options = options
      @connected = false
      @channels = []
    end

    def start
      @connected = true
      self
    end

    def close
      @connected = false
      @channels.each(&:close)
    end

    def connected?
      @connected
    end

    def create_channel
      channel = MockChannel.new(self)
      @channels << channel
      channel
    end

    def on_error(&block)
      @error_callback = block
    end

    def trigger_error(error)
      @error_callback&.call(error)
    end
  end

  class MockChannel
    attr_reader :open, :prefetch_count, :connection, :exchanges, :queues

    def initialize(connection)
      @connection = connection
      @open = true
      @exchanges = {}
      @queues = {}
      @prefetch_count = 1
      @acked_tags = []
      @rejected_tags = []
    end

    def open?
      @open
    end

    def close
      @open = false
    end

    def prefetch(count)
      @prefetch_count = count
    end

    def exchange(name, type: :topic, durable: true)
      @exchanges[name] ||= MockExchange.new(name, type, durable, self)
    end

    def queue(name, durable: true, auto_delete: false)
      @queues[name] ||= MockQueue.new(name, durable: durable, auto_delete: auto_delete, channel: self)
    end

    def ack(delivery_tag)
      @acked_tags << delivery_tag
    end

    def reject(delivery_tag, requeue)
      @rejected_tags << { tag: delivery_tag, requeue: requeue }
    end

    def acked_tags
      @acked_tags
    end

    def rejected_tags
      @rejected_tags
    end

    def on_error(&block)
      @error_callback = block
    end

    def trigger_error(error)
      @error_callback&.call(error)
    end
  end

  class MockExchange
    attr_reader :name, :type, :durable, :published_messages, :channel

    def initialize(name, type, durable, channel)
      @name = name
      @type = type
      @durable = durable
      @channel = channel
      @published_messages = []
    end

    def publish(payload, routing_key:, persistent: false, timestamp: nil, content_type: nil, headers: {})
      @published_messages << {
        payload: payload,
        routing_key: routing_key,
        persistent: persistent,
        timestamp: timestamp,
        content_type: content_type,
        headers: headers
      }
    end

    def published_message_count
      @published_messages.length
    end

    def last_published_message
      @published_messages.last
    end

    def find_messages_by_routing_key(key)
      @published_messages.select { |msg| msg[:routing_key] == key }
    end

    def clear_published_messages
      @published_messages.clear
    end
  end

  class MockQueue
    attr_reader :name, :options, :bindings, :consumers, :channel

    def initialize(name, durable: true, auto_delete: false, channel: nil)
      @name = name
      @options = { durable: durable, auto_delete: auto_delete }
      @channel = channel
      @bindings = []
      @consumers = []
      @messages = []
    end

    def bind(exchange, routing_key:)
      @bindings << { exchange: exchange, routing_key: routing_key }
      self
    end

    def subscribe(manual_ack: false, block: false, &handler)
      consumer = MockConsumer.new(self, handler, manual_ack: manual_ack, blocking: !block)
      @consumers << consumer
      consumer
    end

    def push_message(delivery_info, properties, payload)
      @messages << { delivery_info: delivery_info, properties: properties, payload: payload }
      @consumers.each do |consumer|
        consumer.deliver_message(delivery_info, properties, payload) unless consumer.cancelled?
      end
    end

    def message_count
      @messages.length
    end

    def binding_count
      @bindings.length
    end

    def consumer_count
      @consumers.count { |c| !c.cancelled? }
    end
  end

  class MockConsumer
    attr_reader :queue, :handler, :cancelled, :delivered_messages

    def initialize(queue, handler, manual_ack: false, blocking: false)
      @queue = queue
      @handler = handler
      @manual_ack = manual_ack
      @blocking = blocking
      @cancelled = false
      @delivered_messages = []
    end

    def cancel
      @cancelled = true
    end

    def cancelled?
      @cancelled
    end

    def deliver_message(delivery_info, properties, payload)
      return if cancelled?

      @delivered_messages << { delivery_info: delivery_info, properties: properties, payload: payload }
      @handler&.call(delivery_info, properties, payload)
    end

    def message_count
      @delivered_messages.length
    end
  end

  # Mock delivery info
  class MockDeliveryInfo
    attr_accessor :delivery_tag, :routing_key, :exchange, :redelivered

    def initialize(delivery_tag:, routing_key:, exchange: 'test_exchange', redelivered: false)
      @delivery_tag = delivery_tag
      @routing_key = routing_key
      @exchange = exchange
      @redelivered = redelivered
    end
  end

  # Mock message properties
  class MockProperties
    attr_accessor :headers, :content_type, :timestamp, :message_id

    def initialize(headers: {}, content_type: 'application/json', timestamp: Time.now.to_i, message_id: nil)
      @headers = headers
      @content_type = content_type
      @timestamp = timestamp
      @message_id = message_id || SecureRandom.uuid
    end
  end
end
