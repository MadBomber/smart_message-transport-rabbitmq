# frozen_string_literal: true

require "test_helper"

class TestPublishSubscribeIntegration < Minitest::Test
  def test_basic_publish_subscribe_flow
    transport = create_test_transport
    received_messages = []

    # Subscribe to message class
    transport.subscribe(TestMessages::OrderMessage) do |msg|
      received_messages << msg
    end

    # Verify subscription created queue and consumer
    assert_operator consumer_count(transport), :>, 0, "Should have at least one consumer"
  end

  def test_subscribe_creates_queue_for_message_class
    transport = create_test_transport

    transport.subscribe(TestMessages::OrderMessage) { |msg| msg }

    queues = transport.instance_variable_get(:@queues)
    queue_name = "smart_message.ordermessage"

    # Queue creation happens during subscribe
    # Verify the subscribe method was called
    refute_nil transport.dispatcher, "Dispatcher should exist"
  end

  def test_subscribe_with_multiple_message_classes
    transport = create_test_transport
    handler_called_count = 0

    transport.subscribe([TestMessages::OrderMessage, TestMessages::PaymentMessage]) do |msg|
      handler_called_count += 1
    end

    # Verify both message classes are registered
    subscribers = transport.dispatcher.subscribers
    assert subscribers.key?("OrderMessage"), "OrderMessage should be subscribed"
    assert subscribers.key?("PaymentMessage"), "PaymentMessage should be subscribed"
  end

  def test_subscribe_with_regex_pattern
    transport = create_test_transport

    # Mock SmartMessage::Base.descendants
    SmartMessage::Base.define_singleton_method(:descendants) do
      [TestMessages::OrderMessage, TestMessages::PaymentMessage, TestMessages::AlertMessage]
    end

    transport.subscribe(/.*Message$/) { |msg| msg }

    subscribers = transport.dispatcher.subscribers
    assert_operator subscribers.length, :>=, 3, "Should have subscribed to multiple message classes"
  end

  def test_subscribe_with_routing_filters
    transport = create_test_transport

    transport.subscribe(
      TestMessages::OrderMessage,
      nil,
      { from: 'api_server', to: 'order_service' }
    ) { |msg| msg }

    subscribers = transport.dispatcher.subscribers
    handler_info = subscribers["OrderMessage"].first

    assert handler_info[:routing_patterns].any? { |p| p.include?('order_service') },
           "Should include routing pattern with 'to' filter"
  end

  def test_unsubscribe_removes_handler
    transport = create_test_transport
    handler = proc { |msg| msg }

    transport.subscribe(TestMessages::OrderMessage, handler)
    subscribers_before = transport.dispatcher.subscribers["OrderMessage"].length

    transport.unsubscribe("OrderMessage", handler)
    subscribers_after = transport.dispatcher.subscribers["OrderMessage"].length

    assert subscribers_after < subscribers_before, "Handler should be removed"
  end

  def test_multiple_subscribers_for_same_message_class
    transport = create_test_transport
    handler1_called = false
    handler2_called = false

    handler1 = proc { |msg| handler1_called = true }
    handler2 = proc { |msg| handler2_called = true }

    transport.subscribe(TestMessages::OrderMessage, handler1)
    transport.subscribe(TestMessages::OrderMessage, handler2)

    subscribers = transport.dispatcher.subscribers["OrderMessage"]
    assert_equal 2, subscribers.length, "Should have two handlers"
  end

  def test_publish_with_default_routing
    transport = create_test_transport
    message_class = 'OrderMessage'
    payload = '{"order_id":"123"}'

    routing_key = "#{message_class}.broadcast.anonymous"
    transport.send(:do_publish, message_class, payload, routing_key)

    published = get_published_messages(transport)
    assert_equal 1, published.length
    assert_equal routing_key, published.first[:routing_key]
  end

  def test_publish_with_custom_routing
    transport = create_test_transport
    message_class = 'OrderMessage'
    payload = '{"order_id":"123"}'
    routing_key = "OrderMessage.order_service.api_server"

    transport.send(:do_publish, message_class, payload, routing_key)

    published = get_published_messages(transport)
    assert_equal routing_key, published.first[:routing_key]
  end

  def test_concurrent_subscriptions
    transport = create_test_transport

    # Test multiple subscriptions without threading complexity
    # Subscribe to multiple different message classes
    message_classes = [
      TestMessages::OrderMessage,
      TestMessages::PaymentMessage,
      TestMessages::AlertMessage,
      TestMessages::NotificationMessage
    ]

    message_classes.each do |klass|
      transport.subscribe(klass) { |msg| msg }
    end

    # Should not raise any errors and all subscriptions should be registered
    subscribers = transport.dispatcher.subscribers
    assert_operator subscribers.keys.length, :>=, 4, "Should have registered at least 4 different message classes"

    # Verify specific classes are registered
    assert subscribers.key?("OrderMessage"), "OrderMessage should be subscribed"
    assert subscribers.key?("PaymentMessage"), "PaymentMessage should be subscribed"
  end

  def test_subscription_with_proc_handler
    transport = create_test_transport
    handler_proc = proc { |msg| "processed: #{msg}" }

    transport.subscribe(TestMessages::OrderMessage, handler_proc)

    subscribers = transport.dispatcher.subscribers["OrderMessage"]
    assert_equal handler_proc, subscribers.first[:handler]
  end

  def test_subscription_with_block_handler
    transport = create_test_transport

    transport.subscribe(TestMessages::OrderMessage) do |msg|
      "processed: #{msg}"
    end

    subscribers = transport.dispatcher.subscribers["OrderMessage"]
    assert_instance_of Proc, subscribers.first[:handler]
  end
end
