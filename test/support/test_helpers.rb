# frozen_string_literal: true

require 'timeout'

module TestHelpers
  # RabbitMQ test configuration
  TEST_RABBITMQ_CONFIG = {
    host: ENV['RABBITMQ_HOST'] || 'localhost',
    port: ENV['RABBITMQ_PORT']&.to_i || 5672,
    username: ENV['RABBITMQ_USERNAME'] || 'guest',
    password: ENV['RABBITMQ_PASSWORD'] || 'guest',
    vhost: ENV['RABBITMQ_VHOST'] || '/',
    exchange_name: 'test_smart_message'
  }.freeze

  # Check if RabbitMQ is available
  def rabbitmq_available?
    require 'bunny'
    connection = Bunny.new(TEST_RABBITMQ_CONFIG.slice(:host, :port, :username, :password, :vhost))
    connection.start
    connection.close
    true
  rescue => e
    false
  end

  # Skip test if RabbitMQ is not available
  def skip_without_rabbitmq
    skip "RabbitMQ not available at #{TEST_RABBITMQ_CONFIG[:host]}:#{TEST_RABBITMQ_CONFIG[:port]}" unless rabbitmq_available?
  end

  # Create a test transport with real RabbitMQ connection
  def create_test_transport(**options)
    skip_without_rabbitmq

    config = TEST_RABBITMQ_CONFIG.merge(options)
    config[:serializer] ||= MockSerializer.new

    transport = SmartMessage::Transport::RabbitMQ.new(**config)
    transport.connect

    # Store for cleanup
    @test_transports ||= []
    @test_transports << transport

    transport
  end

  # Execute block with a test transport
  def with_test_transport(**options, &block)
    transport = create_test_transport(**options)
    yield transport
  ensure
    cleanup_transport(transport)
  end

  # Cleanup transport and its resources
  def cleanup_transport(transport)
    return unless transport

    begin
      # Delete all test queues
      channel = transport.instance_variable_get(:@channel)
      queues = transport.instance_variable_get(:@queues)

      queues.each_key do |queue_name|
        channel.queue(queue_name).delete rescue nil
      end

      transport.disconnect
    rescue => e
      # Ignore cleanup errors
    end
  end

  # Cleanup all test transports
  def cleanup_all_transports
    return unless @test_transports

    @test_transports.each do |transport|
      cleanup_transport(transport)
    end
    @test_transports.clear
  end

  # Clean up test exchange
  def cleanup_test_exchange
    skip_without_rabbitmq

    begin
      require 'bunny'
      connection = Bunny.new(TEST_RABBITMQ_CONFIG.slice(:host, :port, :username, :password, :vhost))
      connection.start
      channel = connection.create_channel

      # Delete test exchange if it exists
      channel.exchange_delete(TEST_RABBITMQ_CONFIG[:exchange_name]) rescue nil

      connection.close
    rescue => e
      # Ignore cleanup errors
    end
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
  def wait_for_message(timeout: 2, &block)
    result = wait_for(timeout: timeout, &block)
    flunk "Message not received within #{timeout} seconds" unless result
    result
  end

  # Assert that a message was published
  def assert_published(transport, routing_key, message: nil)
    # With real RabbitMQ, we need to subscribe and wait for the message
    received = []

    channel = transport.instance_variable_get(:@channel)
    exchange = transport.instance_variable_get(:@exchange)

    # Create temporary queue to check for message
    temp_queue = channel.queue("", exclusive: true, auto_delete: true)
    temp_queue.bind(exchange, routing_key: routing_key)

    # Try to get message (non-blocking)
    delivery_info, properties, payload = temp_queue.pop

    if delivery_info
      received << payload
      temp_queue.delete
    end

    assert received.any?, "Expected message with routing key '#{routing_key}' to be published"
  end

  # Get published message count (approximation with real RabbitMQ)
  def get_published_message_count(transport, queue_name)
    channel = transport.instance_variable_get(:@channel)
    queue = channel.queue(queue_name, passive: true)
    queue.message_count
  rescue Bunny::NotFound
    0
  end

  # Purge a queue
  def purge_queue(transport, queue_name)
    channel = transport.instance_variable_get(:@channel)
    channel.queue(queue_name).purge rescue nil
  end

  # Create mock serializer
  def create_mock_serializer
    MockSerializer.new
  end

  # Create test message
  def create_test_message(klass, **attributes)
    klass.new(**attributes)
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

  # Minitest hooks for cleanup
  def setup
    super if defined?(super)
    @test_transports = []
  end

  def teardown
    cleanup_all_transports
    super if defined?(super)
  end
end
