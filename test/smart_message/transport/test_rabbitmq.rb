# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class SmartMessage::Transport::TestRabbitmq < Minitest::Test
  def setup
    @serializer = MockSerializer.new
    @transport = SmartMessage::Transport::RabbitMQ.new(serializer: @serializer)
  end

  def test_that_it_has_a_version_number
    refute_nil ::SmartMessage::Transport::Rabbitmq::VERSION
  end

  def test_constructor_requires_serializer
    assert_raises(ArgumentError) do
      SmartMessage::Transport::RabbitMQ.new
    end
  end

  def test_constructor_accepts_serializer
    transport = SmartMessage::Transport::RabbitMQ.new(serializer: @serializer)
    assert_equal @serializer, transport.serializer
  end

  def test_default_options
    options = @transport.default_options
    assert_equal 'localhost', options[:host]
    assert_equal 5672, options[:port]
    assert_equal :topic, options[:exchange_type]
  end

  def test_build_standard_routing_key_integration
    # Create a mock message instance
    message = MockMessage.new
    
    # Test default routing key
    routing_key = @transport.send(:build_standard_routing_key, message)
    assert_equal "MockMessage.broadcast.anonymous", routing_key
    
    # Test with routing options
    routing_key = @transport.send(:build_standard_routing_key, message, 
                                  to: 'order_service', from: 'api_server')
    assert_equal "MockMessage.order_service.api_server", routing_key
  end

  def test_sanitize_routing_component
    assert_equal "api-server", @transport.send(:sanitize_routing_component, "api-server")
    assert_equal "my_service", @transport.send(:sanitize_routing_component, "my.service")
    assert_equal "test_123", @transport.send(:sanitize_routing_component, "test@123")
  end

  def test_create_dispatcher_returns_rabbitmq_dispatcher
    dispatcher = @transport.send(:create_dispatcher)
    assert_instance_of SmartMessage::Transport::RabbitMQDispatcher, dispatcher
  end

  def test_connected_returns_true_when_connected
    # The transport connects during initialization via configure method
    # So by default, a new transport instance should be connected
    assert @transport.connected?
    
    # Verify the connection objects are set
    connection = @transport.instance_variable_get(:@connection)
    channel = @transport.instance_variable_get(:@channel)
    
    refute_nil connection
    refute_nil channel
  end
end

# Mock classes for testing
class MockSerializer
  def encode(message)
    "encoded_#{message.class.name}"
  end
  
  def decode(data)
    "decoded_#{data}"
  end
end

class MockMessage
  def class
    MockMessage
  end
  
  def self.to_s
    "MockMessage"
  end
  
  def _sm_header
    MockHeader.new
  end
end

class MockHeader
  attr_accessor :to, :from
  
  def initialize
    @to = nil
    @from = nil
  end
end
