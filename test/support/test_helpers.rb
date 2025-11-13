# frozen_string_literal: true

require 'timeout'

module TestHelpers
  # Create a test transport with mocked RabbitMQ connection
  def create_test_transport(**options)
    defaults = {
      serializer: MockSerializer.new,
      host: 'localhost',
      port: 5672,
      exchange_name: 'test_exchange'
    }

    transport = SmartMessage::Transport::RabbitMQ.new(**defaults.merge(options))

    # Replace connection with mock
    mock_connection = MockRabbitMQ::MockConnection.new
    mock_connection.start
    mock_channel = mock_connection.create_channel
    mock_exchange = mock_channel.exchange(
      defaults.merge(options)[:exchange_name],
      type: :topic,
      durable: true
    )

    transport.instance_variable_set(:@connection, mock_connection)
    transport.instance_variable_set(:@channel, mock_channel)
    transport.instance_variable_set(:@exchange, mock_exchange)
    transport.instance_variable_set(:@queues, {})
    transport.instance_variable_set(:@consumers, {})

    transport
  end

  # Execute block with a test transport
  def with_test_transport(**options, &block)
    transport = create_test_transport(**options)
    yield transport
  ensure
    transport&.disconnect rescue nil
  end

  # Wait for a condition to be met within timeout
  def wait_for(timeout: 1, interval: 0.01, &block)
    Timeout.timeout(timeout) do
      loop do
        result = yield
        return result if result
        sleep interval
      end
    end
  rescue Timeout::Error
    nil
  end

  # Wait for a message to be received
  def wait_for_message(timeout: 1, &block)
    result = wait_for(timeout: timeout, &block)
    flunk "Message not received within #{timeout} seconds" unless result
    result
  end

  # Assert that a message was published with specific routing key
  def assert_published(transport, routing_key, message: nil)
    exchange = transport.instance_variable_get(:@exchange)
    published_messages = exchange.published_messages

    matching = if message
      published_messages.any? do |msg|
        msg[:routing_key] == routing_key && msg[:payload].include?(message)
      end
    else
      published_messages.any? { |msg| msg[:routing_key] == routing_key }
    end

    assert matching, "Expected message with routing key '#{routing_key}' to be published"
  end

  # Refute that a message was published with specific routing key
  def refute_published(transport, routing_key)
    exchange = transport.instance_variable_get(:@exchange)
    published = exchange.published_messages.any? do |msg|
      msg[:routing_key] == routing_key
    end
    refute published, "Expected no message with routing key '#{routing_key}' to be published"
  end

  # Get published messages from transport
  def get_published_messages(transport)
    exchange = transport.instance_variable_get(:@exchange)
    exchange.published_messages
  end

  # Clear published messages
  def clear_published_messages(transport)
    exchange = transport.instance_variable_get(:@exchange)
    exchange.clear_published_messages
  end

  # Get queue for message class
  def get_queue(transport, queue_name)
    channel = transport.instance_variable_get(:@channel)
    channel.queues[queue_name]
  end

  # Simulate message reception
  def simulate_message_reception(transport, message_class, payload, routing_key)
    delivery_info = MockRabbitMQ::MockDeliveryInfo.new(
      delivery_tag: rand(1000),
      routing_key: routing_key
    )

    properties = MockRabbitMQ::MockProperties.new(
      headers: { 'message_class' => message_class }
    )

    transport.send(:receive, message_class, payload)
  end

  # Create mock serializer
  def create_mock_serializer
    MockSerializer.new
  end

  # Create test message
  def create_test_message(klass, **attributes)
    klass.new(**attributes)
  end

  # Assert circuit breaker state
  def assert_circuit_state(transport, circuit_name, expected_state)
    # This will be implemented when circuit breaker is added
    # For now, just skip
    skip "Circuit breaker not yet implemented"
  end

  # Assert consumer exists for queue
  def assert_consumer_exists(transport, queue_name)
    consumers = transport.instance_variable_get(:@consumers)
    assert consumers.key?(queue_name), "Expected consumer for queue '#{queue_name}'"
  end

  # Refute consumer exists for queue
  def refute_consumer_exists(transport, queue_name)
    consumers = transport.instance_variable_get(:@consumers)
    refute consumers.key?(queue_name), "Expected no consumer for queue '#{queue_name}'"
  end

  # Get consumer count
  def consumer_count(transport)
    consumers = transport.instance_variable_get(:@consumers)
    consumers.length
  end

  # Get queue count
  def queue_count(transport)
    queues = transport.instance_variable_get(:@queues)
    queues.length
  end
end
