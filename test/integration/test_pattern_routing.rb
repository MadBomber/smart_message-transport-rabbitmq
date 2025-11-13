# frozen_string_literal: true

require "test_helper"

class TestPatternRouting < Minitest::Test
  def setup
    @transport = create_test_transport
  end

  def test_subscribe_pattern_creates_queue
    pattern = "OrderMessage.*.*"

    @transport.subscribe_pattern(pattern, :process, {})

    channel = @transport.instance_variable_get(:@channel)
    queues = channel.queues

    pattern_queue_name = @transport.send(:derive_pattern_queue_name, pattern)
    assert queues.key?(pattern_queue_name), "Pattern queue should be created"
  end

  def test_subscribe_pattern_binds_queue_to_exchange
    pattern = "OrderMessage.*.*"

    @transport.subscribe_pattern(pattern, :process, {})

    channel = @transport.instance_variable_get(:@channel)
    pattern_queue_name = @transport.send(:derive_pattern_queue_name, pattern)
    queue = channel.queues[pattern_queue_name]

    assert queue, "Queue should exist"
    assert_operator queue.bindings.length, :>, 0, "Queue should have bindings"
    assert_equal pattern, queue.bindings.first[:routing_key]
  end

  def test_subscribe_pattern_creates_consumer
    pattern = "OrderMessage.*.*"

    @transport.subscribe_pattern(pattern, :process, {})

    consumers = @transport.instance_variable_get(:@consumers)
    pattern_queue_name = @transport.send(:derive_pattern_queue_name, pattern)

    assert consumers.key?(pattern_queue_name), "Consumer should be created for pattern"
  end

  def test_subscribe_to_recipient_pattern
    recipient_id = 'my_service'

    @transport.subscribe_to_recipient(recipient_id)

    # Verify pattern was created with recipient filter
    consumers = @transport.instance_variable_get(:@consumers)
    assert_operator consumers.length, :>, 0, "Consumer should be created"
  end

  def test_subscribe_from_sender_pattern
    sender_id = 'api_server'

    @transport.subscribe_from_sender(sender_id)

    # Verify pattern was created with sender filter
    consumers = @transport.instance_variable_get(:@consumers)
    assert_operator consumers.length, :>, 0, "Consumer should be created"
  end

  def test_subscribe_to_type_pattern
    message_type = 'OrderMessage'

    @transport.subscribe_to_type(message_type)

    # Verify pattern was created for message type
    consumers = @transport.instance_variable_get(:@consumers)
    assert_operator consumers.length, :>, 0, "Consumer should be created"
  end

  def test_subscribe_to_alerts_creates_multiple_patterns
    @transport.subscribe_to_alerts

    # Should create consumers for multiple alert patterns
    consumers = @transport.instance_variable_get(:@consumers)
    assert_operator consumers.length, :>, 1, "Should create multiple alert consumers"
  end

  def test_subscribe_to_broadcasts_pattern
    @transport.subscribe_to_broadcasts

    # Verify broadcast pattern was created
    consumers = @transport.instance_variable_get(:@consumers)
    assert_operator consumers.length, :>, 0, "Broadcast consumer should be created"
  end

  def test_wildcard_pattern_single_word
    pattern = "OrderMessage.*.api_server"

    @transport.subscribe_pattern(pattern, :process, {})

    # Should create queue and consumer with wildcard pattern
    channel = @transport.instance_variable_get(:@channel)
    pattern_queue_name = @transport.send(:derive_pattern_queue_name, pattern)
    queue = channel.queues[pattern_queue_name]

    assert queue, "Queue should exist for wildcard pattern"
  end

  def test_wildcard_pattern_multiple_words
    pattern = "OrderMessage.#"

    @transport.subscribe_pattern(pattern, :process, {})

    # Should create queue and consumer with multi-word wildcard
    channel = @transport.instance_variable_get(:@channel)
    pattern_queue_name = @transport.send(:derive_pattern_queue_name, pattern)
    queue = channel.queues[pattern_queue_name]

    assert queue, "Queue should exist for multi-word wildcard pattern"
  end

  def test_complex_pattern_with_multiple_wildcards
    pattern = "*.ordermessage.#.service"

    @transport.subscribe_pattern(pattern, :process, {})

    # Should handle complex patterns
    consumers = @transport.instance_variable_get(:@consumers)
    assert_operator consumers.length, :>, 0, "Consumer should handle complex patterns"
  end

  def test_sanitize_for_routing_key_in_patterns
    # Test that special characters are sanitized in patterns
    recipient = 'service@domain.com'
    sanitized = @transport.send(:sanitize_for_routing_key, recipient)

    refute_includes sanitized, '@'
    refute_includes sanitized, '.'
    assert_match /^[a-z0-9_\-]+$/, sanitized
  end

  def test_multiple_pattern_subscriptions
    patterns = [
      "OrderMessage.*.*",
      "PaymentMessage.*.*",
      "AlertMessage.*.*"
    ]

    patterns.each do |pattern|
      @transport.subscribe_pattern(pattern, :process, {})
    end

    consumers = @transport.instance_variable_get(:@consumers)
    assert_operator consumers.length, :>=, 3, "Should create consumers for all patterns"
  end

  def test_pattern_subscription_doesnt_interfere_with_regular_subscription
    # Regular subscription
    @transport.subscribe(TestMessages::OrderMessage) { |msg| msg }

    # Pattern subscription
    @transport.subscribe_pattern("PaymentMessage.*.*", :process, {})

    # Both should coexist
    assert_operator @transport.dispatcher.subscribers.length, :>, 0
    consumers = @transport.instance_variable_get(:@consumers)
    assert_operator consumers.length, :>, 0
  end
end
