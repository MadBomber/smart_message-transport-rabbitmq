#!/usr/bin/env ruby
# frozen_string_literal: true

# Enhanced RabbitMQ Transport Usage Examples
# This file demonstrates how to use the enhanced routing capabilities

require_relative '../lib/smart_message/transport/rabbitmq'

# Example message classes
class OrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :customer_id, required: true
  property :amount, required: true
  
  def process
    puts "Processing order #{order_id} for customer #{customer_id}: $#{amount}"
  end
end

class AlertMessage < SmartMessage::Base
  property :severity, required: true
  property :message, required: true
  property :service, required: true
  
  def process
    puts "ALERT [#{severity}] from #{service}: #{message}"
  end
end

class SystemMessage < SmartMessage::Base
  property :type, required: true
  property :data
  
  def process
    puts "System #{type}: #{data}"
  end
end

# Initialize transport
transport = SmartMessage::Transport::RabbitMQ.new(
  host: 'localhost',
  port: 5672,
  exchange_name: 'smart_message_demo'
)

transport.connect

puts "=== Enhanced RabbitMQ Routing Demo ==="
puts

# Example 1: Basic pattern subscriptions
puts "1. Setting up basic pattern subscriptions..."

# Subscribe to all messages sent to 'order_service'
transport.subscribe_to_recipient('order_service')
puts "   ✓ Subscribed to all messages for order_service"

# Subscribe to all messages from 'payment_gateway'
transport.subscribe_from_sender('payment_gateway')
puts "   ✓ Subscribed to all messages from payment_gateway"

# Subscribe to all alerts
transport.subscribe_to_alerts
puts "   ✓ Subscribed to all alert messages"

# Subscribe to all broadcasts
transport.subscribe_to_broadcasts
puts "   ✓ Subscribed to all broadcast messages"

puts

# Example 2: Advanced pattern subscriptions
puts "2. Setting up advanced pattern subscriptions..."

# Subscribe to specific patterns
transport.subscribe_pattern("#.*.user_123", :process)
puts "   ✓ Subscribed to all messages for user_123"

transport.subscribe_pattern("emergency.#.*.*", :process)
puts "   ✓ Subscribed to all emergency messages"

transport.subscribe_pattern("*.ordermessage.payment_gateway.*", :process)
puts "   ✓ Subscribed to order messages from payment_gateway"

puts

# Example 3: Fluent API subscriptions
puts "3. Setting up fluent API subscriptions..."

# Complex subscription using fluent API
transport.where
  .from('api_server')
  .to('order_service')
  .type('ordermessage')
  .subscribe
puts "   ✓ Subscribed to order messages from api_server to order_service"

transport.where
  .namespace('system')
  .to('monitor')
  .subscribe
puts "   ✓ Subscribed to all system messages sent to monitor"

puts

# Example 4: Publishing with enhanced routing
puts "4. Publishing messages with enhanced routing..."

# Create messages with routing information
order_msg = OrderMessage.new(
  order_id: "ORD-001",
  customer_id: "CUST-123",
  amount: 99.99
)

# Set routing information in header
order_msg._sm_header.from = 'api_server'
order_msg._sm_header.to = 'order_service'

alert_msg = AlertMessage.new(
  severity: 'critical',
  message: 'Database connection lost',
  service: 'order_db'
)

# Alert to monitoring system
alert_msg._sm_header.from = 'order_db'
alert_msg._sm_header.to = 'monitor'

system_msg = SystemMessage.new(
  type: 'heartbeat',
  data: { timestamp: Time.now.to_i, status: 'ok' }
)

# Broadcast system message
system_msg._sm_header.from = 'api_server'
system_msg._sm_header.to = 'broadcast'

# Publish messages
puts "Publishing order message (api_server → order_service)..."
order_msg.publish

puts "Publishing alert message (order_db → monitor)..."
alert_msg.publish

puts "Publishing system broadcast (api_server → broadcast)..."
system_msg.publish

puts

# Example 5: Dynamic subscription based on runtime conditions
puts "5. Dynamic subscription patterns..."

user_id = "user_#{rand(1000)}"
service_id = "service_#{rand(100)}"

# Subscribe to messages for a dynamic user
transport.subscribe_to_recipient(user_id)
puts "   ✓ Dynamically subscribed to messages for #{user_id}"

# Subscribe to messages from a dynamic service
transport.subscribe_from_sender(service_id)
puts "   ✓ Dynamically subscribed to messages from #{service_id}"

puts

# Example 6: Monitoring and debugging patterns
puts "6. Monitoring and debugging patterns..."

if ENV['DEBUG']
  # In debug mode, log all traffic
  transport.subscribe_pattern("#", :process)
  puts "   ✓ DEBUG: Subscribed to ALL messages"
end

# Monitor specific communication channels
transport.subscribe_pattern("*.*.payment_gateway.order_service", :process)
puts "   ✓ Monitoring payment_gateway → order_service communication"

transport.subscribe_pattern("emergency.#.*.*", :process)
puts "   ✓ Monitoring all emergency traffic"

puts

# Example 7: Cleanup and shutdown
puts "7. Cleanup..."

# In a real application, you'd handle shutdown gracefully
at_exit do
  puts "Shutting down transport..."
  transport.disconnect
  puts "Transport disconnected."
end

puts "Demo setup complete! Messages are now being routed based on enhanced patterns."
puts "Run this script and publish messages to see the routing in action."
puts
puts "Example routing keys that will be generated:"
puts "  ordermessage → ordermessage.api_server.order_service"
puts "  alertmessage → alertmessage.order_db.monitor"
puts "  systemmessage → systemmessage.api_server.broadcast"
puts
puts "Example subscription patterns in effect:"
puts "  #.*.order_service        → All messages TO order_service"
puts "  #.payment_gateway.*      → All messages FROM payment_gateway"
puts "  emergency.#.*.*          → All emergency messages"
puts "  #.*.broadcast            → All broadcast messages"
puts "  *.ordermessage.*.*       → All order messages"

# Keep the script running to process messages
if ARGV.include?('--run')
  puts "\nPress Ctrl+C to exit..."
  begin
    sleep
  rescue Interrupt
    puts "\nShutting down..."
    transport.disconnect
    exit 0
  end
end