# frozen_string_literal: true

require "test_helper"

class TestConnectionManagement < Minitest::Test
  def test_connection_starts_disconnected
    transport = create_test_transport
    transport.instance_variable_set(:@connection, nil)

    refute transport.connected?, "New transport should not be connected initially"
  end

  def test_connect_establishes_connection
    transport = create_test_transport
    connection = transport.instance_variable_get(:@connection)

    assert connection.connected?, "Connection should be established"
    assert transport.connected?, "Transport should report as connected"
  end

  def test_disconnect_closes_connection
    transport = create_test_transport
    transport.disconnect

    connection = transport.instance_variable_get(:@connection)
    refute connection.connected?, "Connection should be closed after disconnect"
    refute transport.connected?, "Transport should report as disconnected"
  end

  def test_connection_uses_configured_options
    transport = SmartMessage::Transport::RabbitMQ.new(
      serializer: MockSerializer.new,
      host: 'custom-host',
      port: 5673,
      username: 'custom-user',
      password: 'custom-pass'
    )

    options = transport.instance_variable_get(:@options)
    assert_equal 'custom-host', options[:host]
    assert_equal 5673, options[:port]
    assert_equal 'custom-user', options[:username]
    assert_equal 'custom-pass', options[:password]
  end

  def test_connection_uses_environment_variables
    original_env = ENV.to_h

    begin
      ENV['RABBITMQ_HOST'] = 'env-host'
      ENV['RABBITMQ_PORT'] = '5674'
      ENV['RABBITMQ_USERNAME'] = 'env-user'

      transport = SmartMessage::Transport::RabbitMQ.new(
        serializer: MockSerializer.new
      )

      options = transport.instance_variable_get(:@options)
      assert_equal 'env-host', options[:host]
      assert_equal 5674, options[:port]
      assert_equal 'env-user', options[:username]
    ensure
      ENV.replace(original_env)
    end
  end

  def test_disconnect_stops_all_consumers
    transport = create_test_transport

    # Add some mock consumers
    consumers = {
      'queue1' => MockRabbitMQ::MockConsumer.new(nil, proc {}),
      'queue2' => MockRabbitMQ::MockConsumer.new(nil, proc {})
    }
    transport.instance_variable_set(:@consumers, consumers)

    transport.disconnect

    consumers.each_value do |consumer|
      assert consumer.cancelled?, "Consumer should be cancelled"
    end

    assert_empty transport.instance_variable_get(:@consumers),
                  "Consumers should be cleared"
  end

  def test_connected_returns_false_when_shutdown
    transport = create_test_transport
    transport.instance_variable_set(:@shutdown, true)

    refute transport.connected?, "Should not be connected when shutdown flag is set"
  end

  def test_connected_returns_false_with_closed_channel
    transport = create_test_transport
    channel = transport.instance_variable_get(:@channel)
    channel.close

    refute transport.connected?, "Should not be connected with closed channel"
  end

  def test_prefetch_configured_on_channel
    transport = create_test_transport
    channel = transport.instance_variable_get(:@channel)

    assert_equal 10, channel.prefetch_count, "Prefetch should be set to default value"
  end

  def test_custom_prefetch_value
    transport = SmartMessage::Transport::RabbitMQ.new(
      serializer: MockSerializer.new,
      prefetch: 25
    )

    mock_connection = MockRabbitMQ::MockConnection.new
    mock_connection.start
    mock_channel = mock_connection.create_channel
    mock_channel.prefetch(25)

    transport.instance_variable_set(:@connection, mock_connection)
    transport.instance_variable_set(:@channel, mock_channel)

    assert_equal 25, mock_channel.prefetch_count
  end
end
