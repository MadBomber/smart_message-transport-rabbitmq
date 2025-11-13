# frozen_string_literal: true

require "test_helper"

class TestPublishing < Minitest::Test
  def test_publish_sends_message_to_exchange
    transport = create_test_transport
    message = TestMessages::TestMessage.new(data: 'test data')

    routing_key = "TestMessage.broadcast.anonymous"
    transport.send(:do_publish, 'TestMessage', '{"data":"test data"}', routing_key)

    assert_published(transport, routing_key)
  end

  def test_publish_includes_routing_key
    transport = create_test_transport
    message_class = 'TestMessages::OrderMessage'
    payload = '{"order_id":"123"}'
    routing_key = "OrderMessage.service.api"

    transport.send(:do_publish, message_class, payload, routing_key)

    published = get_published_messages(transport)
    assert_equal routing_key, published.last[:routing_key]
  end

  def test_publish_includes_message_headers
    transport = create_test_transport
    message_class = 'TestMessages::OrderMessage'
    payload = '{"order_id":"123"}'
    routing_key = "OrderMessage.service.api"

    transport.send(:do_publish, message_class, payload, routing_key, from: 'api', to: 'service')

    published = get_published_messages(transport)
    headers = published.last[:headers]

    assert_equal message_class, headers[:message_class]
    assert_includes headers.keys, :smart_message_version
  end

  def test_publish_marks_messages_as_persistent
    transport = create_test_transport
    message_class = 'TestMessages::OrderMessage'
    payload = '{"order_id":"123"}'
    routing_key = "OrderMessage.service.api"

    transport.send(:do_publish, message_class, payload, routing_key)

    published = get_published_messages(transport)
    assert published.last[:persistent], "Message should be marked as persistent"
  end

  def test_publish_includes_timestamp
    transport = create_test_transport
    message_class = 'TestMessages::OrderMessage'
    payload = '{"order_id":"123"}'
    routing_key = "OrderMessage.service.api"

    before = Time.now.to_i
    transport.send(:do_publish, message_class, payload, routing_key)
    after = Time.now.to_i

    published = get_published_messages(transport)
    timestamp = published.last[:timestamp]

    assert timestamp >= before, "Timestamp should be after start time"
    assert timestamp <= after, "Timestamp should be before end time"
  end

  def test_publish_sets_content_type_to_json
    transport = create_test_transport
    message_class = 'TestMessages::OrderMessage'
    payload = '{"order_id":"123"}'
    routing_key = "OrderMessage.service.api"

    transport.send(:do_publish, message_class, payload, routing_key)

    published = get_published_messages(transport)
    assert_equal 'application/json', published.last[:content_type]
  end

  def test_publish_extracts_routing_components_from_key
    transport = create_test_transport
    message_class = 'TestMessages::OrderMessage'
    payload = '{"order_id":"123"}'
    routing_key = "OrderMessage.order_service.api_server"

    transport.send(:do_publish, message_class, payload, routing_key)

    published = get_published_messages(transport)
    headers = published.last[:headers]

    assert_equal 'api_server', headers[:from]
    assert_equal 'order_service', headers[:to]
  end

  def test_publish_logs_message_details
    transport = create_test_transport
    message_class = 'TestMessages::OrderMessage'
    payload = '{"order_id":"123"}'
    routing_key = "OrderMessage.service.api"

    # Should not raise any errors during logging
    assert_silent do
      transport.send(:do_publish, message_class, payload, routing_key)
    end
  end

  def test_multiple_publishes_accumulate
    transport = create_test_transport

    3.times do |i|
      transport.send(:do_publish, 'TestMessage', "{\"id\":#{i}}", "TestMessage.broadcast.anonymous")
    end

    published = get_published_messages(transport)
    assert_equal 3, published.length
  end

  def test_publish_with_large_payload
    transport = create_test_transport
    large_data = 'x' * 10_000  # 10KB payload
    payload = "{\"data\":\"#{large_data}\"}"

    transport.send(:do_publish, 'TestMessage', payload, "TestMessage.broadcast.anonymous")

    published = get_published_messages(transport)
    assert published.last[:payload].include?(large_data)
  end
end
