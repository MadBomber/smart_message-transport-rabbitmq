#!/usr/bin/env ruby
# frozen_string_literal: true

# Enhanced RabbitMQ Transport Usage Examples
# This file demonstrates how to use the enhanced routing capabilities

require 'securerandom'
require 'smart_message'
require_relative '../lib/smart_message/transport/rabbitmq'

# Load message classes
require_relative 'messages/order_message'
require_relative 'messages/alert_message'
require_relative 'messages/system_message'

# Create JSON serializer
serializer = SmartMessage::Serializer::Json.new

# Initialize transport with required serializer parameter
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  host: 'localhost',
  port: 5672,
  exchange_name: 'smart_message_demo'
)

# Configure SmartMessage with transport as default
SmartMessage.configure do |config|
  config.transport = transport
end

# Connect the transport
transport.connect

# Log demo program start
transport.send(:logger).info { "[Demo] Enhanced RabbitMQ Routing Demo started - PID #{Process.pid}" }

puts "Setting up subscriptions..."

# Set up unified subscription API with new architecture
# Subscribe to specific message classes
transport.subscribe(OrderMessage) { |msg| puts "Processing OrderMessage: #{msg.order_id}" }
transport.subscribe(AlertMessage) { |msg| puts "Processing AlertMessage: #{msg.severity} - #{msg.message}" }
transport.subscribe(SystemMessage) { |msg| puts "Processing SystemMessage: #{msg.type}" }

# Subscribe to multiple message classes at once
transport.subscribe([OrderMessage, AlertMessage], nil, { to: 'order_service' }) do |msg|
  puts "Processing #{msg.class.name} targeted to order_service"
end

# Use fluent API for complex routing
transport.where
  .message_class(OrderMessage)
  .from('api_server')
  .to('order_service')
  .subscribe { |msg| puts "API server order for order service: #{msg.order_id}" }

puts "Publishing messages..."

# Create and publish messages using new transport-centric architecture
order_msg = OrderMessage.new(
  order_id: "ORD-001",
  customer_id: "CUST-123",
  amount: 99.99,
  _sm_header: { uuid: SecureRandom.uuid, message_class: 'OrderMessage', from: 'api_server', to: 'order_service' }
)

alert_msg = AlertMessage.new(
  severity: 'critical',
  message: 'Database connection lost',
  service: 'order_db',
  _sm_header: { uuid: SecureRandom.uuid, message_class: 'AlertMessage', from: 'monitor_service', to: 'alert_service' }
)

system_msg = SystemMessage.new(
  type: 'heartbeat',
  data: { timestamp: Time.now.to_i, status: 'ok' },
  _sm_header: { uuid: SecureRandom.uuid, message_class: 'SystemMessage', from: 'system_monitor', to: 'broadcast' }
)

# Publish using new routing options pattern
order_msg.publish(from: 'api_server', to: 'order_service')
alert_msg.publish(from: 'order_db', to: 'monitor')
system_msg.publish(from: 'api_server', to: 'broadcast')

puts "Setting up dynamic subscriptions..."
user_id = "user_#{rand(1000)}"
service_id = "service_#{rand(100)}"

# Subscribe with dynamic routing filters
transport.subscribe([OrderMessage, AlertMessage], nil, { to: user_id }) do |msg|
  puts "Message for user #{user_id}: #{msg.class.name}"
end

transport.subscribe([OrderMessage, AlertMessage], nil, { from: service_id }) do |msg|
  puts "Message from service #{service_id}: #{msg.class.name}"
end

puts "Setting up monitoring patterns..."
if ENV['DEBUG']
  # Subscribe to all message classes for debugging
  transport.subscribe([OrderMessage, AlertMessage, SystemMessage]) do |msg|
    puts "DEBUG: #{msg.class.name} - #{msg.inspect}"
  end
end

# Subscribe with regex pattern for message class matching
transport.subscribe(/.*Message$/) { |msg| puts "Monitoring pattern matched: #{msg.class.name}" }

# In a real application, you'd handle shutdown gracefully
at_exit do
  transport.send(:logger).info { "[Demo] Enhanced RabbitMQ Routing Demo shutting down - PID #{Process.pid}" }
  puts "Shutting down transport..."
  transport.disconnect
  puts "Transport disconnected."
  transport.send(:logger).info { "[Demo] Enhanced RabbitMQ Routing Demo completed - PID #{Process.pid}" }
end

puts "Demo setup complete!"

# Keep the script running to process messages
if ARGV.include?('--run')
  puts "Press Ctrl+C to exit..."
  begin
    sleep
  rescue Interrupt
    puts "Shutting down..."
    transport.disconnect
    exit 0
  end
end
