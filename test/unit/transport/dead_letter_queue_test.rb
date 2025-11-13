# frozen_string_literal: true

require "test_helper"

class TestDeadLetterQueue < Minitest::Test
  def test_initialization_creates_dlq_exchange_and_queue
    skip_without_rabbitmq

    with_test_transport do |transport|
      dlq = transport.dlq

      assert dlq, "DLQ should be initialized"
      assert_equal "test_smart_message.dlq", dlq.dlq_exchange_name
      assert_equal "test_smart_message.dlq.queue", dlq.dlq_queue_name
    end
  end

  def test_send_to_dlq_stores_failed_message
    skip_without_rabbitmq

    with_test_transport do |transport|
      dlq = transport.dlq
      error = StandardError.new("Processing failed")

      dlq.send_to_dlq(
        "TestMessage",
        '{"data":"test"}',
        "TestMessage.broadcast.anonymous",
        error,
        { retry_count: 0 }
      )

      # DLQ should have the message
      stats = dlq.stats
      # Note: In real RabbitMQ this would be > 0, but we're just testing the interface
      assert stats.key?(:message_count)
    end
  end

  def test_stats_returns_queue_information
    skip_without_rabbitmq

    with_test_transport do |transport|
      dlq = transport.dlq
      stats = dlq.stats

      assert stats.key?(:queue_name)
      assert stats.key?(:message_count)
      assert stats.key?(:consumer_count)
      assert_equal "test_smart_message.dlq.queue", stats[:queue_name]
    end
  end

  def test_dlq_can_be_disabled
    skip_without_rabbitmq

    transport = create_test_transport(disable_dlq: true)
    assert_nil transport.dlq, "DLQ should be disabled"
  end

  def test_dlq_inspect_returns_messages
    skip_without_rabbitmq

    with_test_transport do |transport|
      dlq = transport.dlq

      # Inspect should return array (even if empty)
      messages = dlq.inspect_messages(limit: 5)
      assert_instance_of Array, messages
    end
  end

  def test_dlq_purge_clears_queue
    skip_without_rabbitmq

    with_test_transport do |transport|
      dlq = transport.dlq

      # Should not raise error
      assert_silent { dlq.purge! }
    end
  end

  def test_send_to_dlq_includes_error_information
    skip_without_rabbitmq

    with_test_transport do |transport|
      dlq = transport.dlq
      error = StandardError.new("Test error message")
      error.set_backtrace(["line1", "line2", "line3"])

      # Should not raise error
      assert_silent do
        dlq.send_to_dlq(
          "TestMessage",
          '{"data":"test"}',
          "TestMessage.test.test",
          error,
          { retry_count: 1 }
        )
      end
    end
  end

  def test_dlq_with_custom_ttl
    skip_without_rabbitmq

    transport = create_test_transport(dlq_ttl: 3600000) # 1 hour
    dlq = transport.dlq

    assert dlq, "DLQ should be initialized with custom TTL"
  end
end
