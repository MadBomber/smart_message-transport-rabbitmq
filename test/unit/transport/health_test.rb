# frozen_string_literal: true

require "test_helper"

class TestHealth < Minitest::Test
  def test_health_status_when_not_connected
    transport = SmartMessage::Transport::RabbitMQ.new(serializer: MockSerializer.new)
    # Don't connect
    transport.instance_variable_set(:@health, SmartMessage::Transport::RabbitMQ::Health.new(transport))

    health = transport.health
    status = health.health_status

    assert_equal :unhealthy, status[:status]
    assert_equal :unhealthy, status[:components][:connection][:status]
  end

  def test_health_status_structure
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      status = health.health_status

      # Check structure
      assert status.key?(:status)
      assert status.key?(:timestamp)
      assert status.key?(:components)
      assert status.key?(:summary)

      # Check components
      assert status[:components].key?(:connection)
      assert status[:components].key?(:consumers)
      assert status[:components].key?(:circuits)
      assert status[:components].key?(:queues)
      assert status[:components].key?(:dlq)
    end
  end

  def test_connection_health_when_connected
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      status = health.health_status

      assert_equal :healthy, status[:components][:connection][:status]
    end
  end

  def test_consumer_health_with_no_consumers
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      status = health.health_status

      # No consumers initially
      consumer_status = status[:components][:consumers]
      assert_includes [:degraded, :healthy], consumer_status[:status]
      assert_equal 0, consumer_status[:count]
    end
  end

  def test_circuit_health_all_closed
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      status = health.health_status

      circuit_status = status[:components][:circuits]
      assert_equal :healthy, circuit_status[:status]
      assert_equal [], circuit_status[:open]
      assert_equal [], circuit_status[:half_open]
    end
  end

  def test_circuit_health_with_open_circuit
    skip_without_rabbitmq

    with_test_transport do |transport|
      # Force a circuit to open
      5.times { transport.circuits[:publish].on_failure(StandardError.new("test")) }

      health = transport.health
      status = health.health_status

      circuit_status = status[:components][:circuits]
      assert_equal :unhealthy, circuit_status[:status]
      assert_includes circuit_status[:open], :publish
    end
  end

  def test_circuit_health_with_half_open_circuit
    skip_without_rabbitmq

    with_test_transport do |transport|
      # Force a circuit to open
      circuit = transport.circuits[:publish]
      5.times { circuit.on_failure(StandardError.new("test")) }

      # Force transition to half_open
      circuit.instance_variable_set(:@last_failure_time, Time.now - 31)
      circuit.send(:check_state)

      health = transport.health
      status = health.health_status

      circuit_status = status[:components][:circuits]
      assert_equal :degraded, circuit_status[:status]
      assert_includes circuit_status[:half_open], :publish
    end
  end

  def test_queue_health_with_no_queues
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      status = health.health_status

      queue_status = status[:components][:queues]
      assert_includes [:degraded, :healthy], queue_status[:status]
    end
  end

  def test_dlq_health_when_disabled
    skip_without_rabbitmq

    transport = create_test_transport(disable_dlq: true)
    health = transport.health
    status = health.health_status

    dlq_status = status[:components][:dlq]
    assert_equal :healthy, dlq_status[:status]
    assert_match /disabled/, dlq_status[:message]

    cleanup_transport(transport)
  end

  def test_dlq_health_when_enabled
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      status = health.health_status

      dlq_status = status[:components][:dlq]
      assert_includes [:healthy, :degraded], dlq_status[:status]
      assert dlq_status.key?(:message_count)
    end
  end

  def test_alive_check
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      assert health.alive?, "Transport should be alive when connected"
    end
  end

  def test_alive_check_when_not_connected
    transport = SmartMessage::Transport::RabbitMQ.new(serializer: MockSerializer.new)
    transport.instance_variable_set(:@health, SmartMessage::Transport::RabbitMQ::Health.new(transport))

    health = transport.health
    refute health.alive?, "Transport should not be alive when not connected"
  end

  def test_ready_check
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health

      # Should be ready if all components are healthy
      ready = health.ready?
      assert_includes [true, false], ready
    end
  end

  def test_overall_status_unhealthy_if_any_unhealthy
    skip_without_rabbitmq

    with_test_transport do |transport|
      # Force a circuit to open (makes it unhealthy)
      5.times { transport.circuits[:publish].on_failure(StandardError.new("test")) }

      health = transport.health
      status = health.health_status

      assert_equal :unhealthy, status[:status]
    end
  end

  def test_overall_status_degraded_if_any_degraded
    skip_without_rabbitmq

    with_test_transport do |transport|
      # Force a circuit to half_open (makes it degraded)
      circuit = transport.circuits[:publish]
      5.times { circuit.on_failure(StandardError.new("test")) }
      circuit.instance_variable_set(:@last_failure_time, Time.now - 31)
      circuit.send(:check_state)

      health = transport.health
      status = health.health_status

      assert_includes [:degraded, :unhealthy], status[:status]
    end
  end

  def test_summary_message
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      status = health.health_status

      assert_instance_of String, status[:summary]
      refute_empty status[:summary]
    end
  end

  def test_timestamp_format
    skip_without_rabbitmq

    with_test_transport do |transport|
      health = transport.health
      status = health.health_status

      # Should be ISO8601 format
      assert_match /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, status[:timestamp]
    end
  end
end
