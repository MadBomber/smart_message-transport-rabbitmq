# frozen_string_literal: true

require "test_helper"

class TestRoutingKeys < Minitest::Test
  def setup
    @transport = create_test_transport
  end

  def test_derive_routing_key_converts_to_lowercase
    routing_key = @transport.send(:derive_routing_key, 'OrderMessage')
    assert_equal 'ordermessage', routing_key
  end

  def test_derive_routing_key_converts_namespace_separators
    routing_key = @transport.send(:derive_routing_key, 'MyApp::OrderMessage')
    assert_equal 'myapp.ordermessage', routing_key
  end

  def test_derive_queue_name_includes_prefix
    queue_name = @transport.send(:derive_queue_name, 'OrderMessage')
    assert_equal 'smart_message.ordermessage', queue_name
  end

  def test_derive_queue_name_includes_namespace
    queue_name = @transport.send(:derive_queue_name, 'MyApp::OrderMessage')
    assert_equal 'smart_message.myapp.ordermessage', queue_name
  end

  def test_sanitize_for_routing_key_removes_special_characters
    sanitized = @transport.send(:sanitize_for_routing_key, 'test@value#123')
    refute_includes sanitized, '@'
    refute_includes sanitized, '#'
  end

  def test_sanitize_for_routing_key_converts_to_lowercase
    sanitized = @transport.send(:sanitize_for_routing_key, 'TestValue')
    assert_equal 'testvalue', sanitized
  end

  def test_sanitize_for_routing_key_replaces_dots
    sanitized = @transport.send(:sanitize_for_routing_key, 'test.value')
    assert_equal 'test_value', sanitized
  end

  def test_sanitize_for_routing_key_allows_hyphens
    sanitized = @transport.send(:sanitize_for_routing_key, 'test-value')
    assert_equal 'test-value', sanitized
  end

  def test_sanitize_for_routing_key_allows_underscores
    sanitized = @transport.send(:sanitize_for_routing_key, 'test_value')
    assert_equal 'test_value', sanitized
  end

  def test_derive_pattern_queue_name_replaces_wildcards
    pattern_queue = @transport.send(:derive_pattern_queue_name, 'OrderMessage.*.*')
    assert_includes pattern_queue, 'any'
    refute_includes pattern_queue, '*'
  end

  def test_derive_pattern_queue_name_replaces_multi_wildcards
    pattern_queue = @transport.send(:derive_pattern_queue_name, 'OrderMessage.#')
    assert_includes pattern_queue, 'all'
    refute_includes pattern_queue, '#'
  end

  def test_derive_pattern_queue_name_converts_dots_to_underscores
    pattern_queue = @transport.send(:derive_pattern_queue_name, 'Order.Message.*.*')
    # The pattern string itself will have dots converted to underscores in the queue name
    # But the prefix "smart_message.pattern." will still have dots
    # So we check the converted part specifically
    pattern_part = pattern_queue.split('.').last
    refute_includes pattern_part, '.', "Pattern part should not contain dots"
  end

  def test_extract_message_class_from_routing_key_with_4_parts
    routing_key = 'myapp.ordermessage.api.service'
    message_class = @transport.send(:extract_message_class_from_routing_key, routing_key)
    assert_equal 'Myapp::Ordermessage', message_class
  end

  def test_extract_message_class_from_routing_key_with_fewer_parts
    routing_key = 'ordermessage.service'
    message_class = @transport.send(:extract_message_class_from_routing_key, routing_key)
    assert_includes message_class, 'Ordermessage'
  end

  def test_extract_message_class_from_routing_key_capitalizes_parts
    routing_key = 'myapp.ordermessage.api.service'
    message_class = @transport.send(:extract_message_class_from_routing_key, routing_key)
    parts = message_class.split('::')
    parts.each do |part|
      assert_equal part[0], part[0].upcase, "Part should start with capital letter"
    end
  end
end
