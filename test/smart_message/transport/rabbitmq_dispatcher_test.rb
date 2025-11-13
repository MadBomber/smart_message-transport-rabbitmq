# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class TestRabbitMQDispatcher < Minitest::Test
  def setup
    @dispatcher = SmartMessage::Transport::RabbitMQDispatcher.new
  end

  def test_initialization
    assert_instance_of Hash, @dispatcher.subscribers
    assert_empty @dispatcher.subscribers
  end

  def test_add_single_handler
    handler = proc { |msg| "processed" }
    @dispatcher.add("OrderMessage", handler, {})
    
    assert_equal 1, @dispatcher.subscribers["OrderMessage"].length
    assert_equal handler, @dispatcher.subscribers["OrderMessage"].first[:handler]
  end

  def test_add_handler_with_routing_options
    handler = proc { |msg| "processed" }
    options = { from: 'api_server', to: 'order_service' }
    
    @dispatcher.add("OrderMessage", handler, options)
    
    handler_info = @dispatcher.subscribers["OrderMessage"].first
    assert_includes handler_info[:routing_patterns], "OrderMessage.order_service.api_server"
  end

  def test_add_handler_with_array_filters
    handler = proc { |msg| "processed" }
    options = { from: ['api_server', 'web_server'], to: 'order_service' }
    
    @dispatcher.add("OrderMessage", handler, options)
    
    handler_info = @dispatcher.subscribers["OrderMessage"].first
    assert_includes handler_info[:routing_patterns], "OrderMessage.order_service.api_server"
    assert_includes handler_info[:routing_patterns], "OrderMessage.order_service.web_server"
  end

  def test_drop_handler
    handler1 = proc { |msg| "handler1" }
    handler2 = proc { |msg| "handler2" }
    
    @dispatcher.add("OrderMessage", handler1, {})
    @dispatcher.add("OrderMessage", handler2, {})
    
    assert_equal 2, @dispatcher.subscribers["OrderMessage"].length
    
    @dispatcher.drop("OrderMessage", handler1)
    
    assert_equal 1, @dispatcher.subscribers["OrderMessage"].length
    assert_equal handler2, @dispatcher.subscribers["OrderMessage"].first[:handler]
  end

  def test_drop_all_handlers
    handler1 = proc { |msg| "handler1" }
    handler2 = proc { |msg| "handler2" }
    
    @dispatcher.add("OrderMessage", handler1, {})
    @dispatcher.add("OrderMessage", handler2, {})
    @dispatcher.add("PaymentMessage", handler1, {})
    
    @dispatcher.drop_all("OrderMessage")
    
    assert_empty @dispatcher.subscribers["OrderMessage"]
    assert_equal 1, @dispatcher.subscribers["PaymentMessage"].length
  end

  def test_routing_key_matches_exact_match
    patterns = ["OrderMessage.order_service.api_server"]
    
    assert @dispatcher.send(:routing_key_matches?, "OrderMessage.order_service.api_server", patterns)
    refute @dispatcher.send(:routing_key_matches?, "OrderMessage.billing_service.api_server", patterns)
  end

  def test_routing_key_matches_single_wildcard
    patterns = ["OrderMessage.*.api_server"]
    
    assert @dispatcher.send(:routing_key_matches?, "OrderMessage.order_service.api_server", patterns)
    assert @dispatcher.send(:routing_key_matches?, "OrderMessage.billing_service.api_server", patterns)
    refute @dispatcher.send(:routing_key_matches?, "PaymentMessage.order_service.api_server", patterns)
  end

  def test_routing_key_matches_multi_wildcard
    patterns = ["OrderMessage.#"]
    
    assert @dispatcher.send(:routing_key_matches?, "OrderMessage.order_service.api_server", patterns)
    assert @dispatcher.send(:routing_key_matches?, "OrderMessage.billing_service", patterns)
    assert @dispatcher.send(:routing_key_matches?, "OrderMessage.a.b.c.d", patterns)
    refute @dispatcher.send(:routing_key_matches?, "PaymentMessage.order_service.api_server", patterns)
  end

  def test_build_routing_patterns_with_wildcards
    patterns = @dispatcher.send(:build_routing_patterns, "OrderMessage", {})
    assert_includes patterns, "OrderMessage.*.*"
    
    patterns = @dispatcher.send(:build_routing_patterns, "OrderMessage", { to: 'service' })
    assert_includes patterns, "OrderMessage.service.*"
    
    patterns = @dispatcher.send(:build_routing_patterns, "OrderMessage", { from: 'api' })
    assert_includes patterns, "OrderMessage.*.api"
  end

  def test_execute_handler_with_proc
    called = false
    handler = proc { |msg| called = true }
    
    @dispatcher.send(:execute_handler, handler, MockMessage.new)
    
    assert called
  end

  def test_execute_handler_with_string
    # Mock a service class
    mock_service = Minitest::Mock.new
    mock_service.expect(:handle_message, nil, [MockMessage])
    
    # Stub const_get to return our mock service
    Object.define_singleton_method(:const_get) { |name| mock_service if name == "MockService" }
    
    @dispatcher.send(:execute_handler, "MockService.handle_message", MockMessage.new)
    
    mock_service.verify
    
    # Clean up the stub
    Object.singleton_class.remove_method(:const_get)
  end

  def test_route_message_calls_matching_handlers
    handler1_called = false
    handler2_called = false
    
    handler1 = proc { |msg| handler1_called = true }
    handler2 = proc { |msg| handler2_called = true }
    
    # Add handlers with different routing patterns
    @dispatcher.add("MockMessage", handler1, { to: 'service1' })
    @dispatcher.add("MockMessage", handler2, { to: 'service2' })
    
    message = MockMessage.new
    
    # Route with matching key for handler1
    @dispatcher.route(message, "MockMessage.service1.api")
    
    assert handler1_called
    refute handler2_called
  end

  def test_route_message_with_no_routing_key
    handler_called = false
    handler = proc { |msg| handler_called = true }
    
    @dispatcher.add("MockMessage", handler, {})
    
    message = MockMessage.new
    @dispatcher.route(message, nil)
    
    assert handler_called
  end
end

# Mock message class for testing
class MockMessage
  def class
    MockMessage
  end
  
  def self.to_s
    "MockMessage"
  end
end