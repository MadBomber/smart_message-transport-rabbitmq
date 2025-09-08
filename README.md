# SmartMessage::Transport::RabbitMQ

A RabbitMQ transport adapter for the SmartMessage Ruby gem, providing reliable message queuing and routing capabilities with support for various exchange types and advanced routing patterns.

## Features

- **Transport-Centric Architecture**: Centralized serialization and optimized message routing
- **Advanced RabbitMQ Routing**: Leverages RabbitMQ's topic exchange for sophisticated message routing patterns  
- **Standardized 3-Component Routing Keys**: `{message_class}.{to_recipient}.{from_sender}` format
- **Multi-Message Class Subscriptions**: Subscribe to arrays of message classes or regex patterns
- **Fluent Subscription API**: Chainable methods for complex routing conditions
- **RabbitMQ-Native Dispatcher**: Optimized dispatcher that leverages RabbitMQ's built-in pattern matching
- **Wildcard Support**: Automatic wildcard defaulting for missing routing components
- **Circuit Breaker Integration**: Built-in circuit breakers for reliability
- **Connection Recovery**: Automatic reconnection and consumer restart capabilities

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'smart_message-transport-rabbitmq'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install smart_message-transport-rabbitmq
```

## Quick Start

### Basic Setup

```ruby
require 'smart_message'
require 'smart_message/transport/rabbitmq'

# Create serializer (required for transport-centric architecture)
serializer = SmartMessage::Serializer::Json.new

# Initialize RabbitMQ transport with serializer
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  host: 'localhost',
  port: 5672,
  exchange_name: 'my_app_messages'
)

# Configure as default transport
SmartMessage.configure do |config|
  config.transport = transport
end

# Connect
transport.connect
```

### Publishing Messages

```ruby
# Create a message
class OrderMessage < SmartMessage::Base
  property :order_id, String
  property :customer_id, String
  property :amount, Float
end

order = OrderMessage.new(
  order_id: "ORD-123",
  customer_id: "CUST-456", 
  amount: 99.99
)

# Publish with routing options
order.publish(from: 'api_server', to: 'order_service')

# Broadcast message (no 'to' specified)
order.publish(from: 'api_server')

# Using fluent API (if implemented in SmartMessage core)
order.where.from('api_server').to('order_service').publish
```

### Subscribing to Messages

#### Basic Subscription

```ruby
# Subscribe to a single message class
transport.subscribe(OrderMessage) do |message|
  puts "Processing order: #{message.order_id}"
end

# Subscribe with routing filters
transport.subscribe(OrderMessage, nil, { from: 'api_server' }) do |message|
  puts "API server order: #{message.order_id}"
end
```

#### Multi-Message Class Subscriptions

```ruby
# Subscribe to multiple message classes
transport.subscribe([OrderMessage, PaymentMessage]) do |message|
  puts "Processing #{message.class.name}: #{message.inspect}"
end

# Subscribe using regex pattern
transport.subscribe(/.*Message$/) do |message|
  puts "Any message class ending in 'Message': #{message.class.name}"
end
```

#### Fluent Subscription API

```ruby
# Subscribe with fluent API
transport.where
  .message_class(OrderMessage)
  .from('payment_gateway')
  .to('order_service')
  .subscribe { |msg| handle_payment_order(msg) }

# Multiple conditions
transport.where
  .message_class([OrderMessage, RefundMessage])
  .from(['payment_gateway', 'billing_service'])
  .subscribe { |msg| handle_financial_message(msg) }
```

## Routing Architecture

### 3-Component Routing Keys

The RabbitMQ transport uses standardized 3-component routing keys:

```
{message_class}.{to_recipient}.{from_sender}
```

Examples:
- `OrderMessage.order_service.api_server`
- `PaymentMessage.billing_service.payment_gateway` 
- `AlertMessage.broadcast.monitoring_service`

### Wildcard Defaulting

Missing routing components automatically default to wildcards:

```ruby
# No routing specified
message.publish
# Routing key: OrderMessage.broadcast.anonymous

# Only 'to' specified  
message.publish(to: 'order_service')
# Routing key: OrderMessage.order_service.anonymous

# Only 'from' specified
message.publish(from: 'api_server')
# Routing key: OrderMessage.broadcast.api_server
```

### RabbitMQ Pattern Matching

The transport leverages RabbitMQ's topic exchange patterns:

- `*` matches exactly one word
- `#` matches zero or more words

```ruby
# Subscribe to all OrderMessages regardless of routing
transport.subscribe_pattern("OrderMessage.*.*")

# Subscribe to all messages to order_service
transport.subscribe_pattern("*.order_service.*") 

# Subscribe to all messages from api_server
transport.subscribe_pattern("*.*.api_server")

# Subscribe to all emergency messages
transport.subscribe_pattern("*.emergency.*")
```

## Advanced Features

### Connection Configuration

```ruby
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  host: ENV['RABBITMQ_HOST'] || 'localhost',
  port: ENV['RABBITMQ_PORT']&.to_i || 5672,
  username: ENV['RABBITMQ_USERNAME'] || 'guest',
  password: ENV['RABBITMQ_PASSWORD'] || 'guest',
  vhost: ENV['RABBITMQ_VHOST'] || '/',
  exchange_name: 'my_app_messages',
  exchange_type: :topic,
  exchange_durable: true,
  queue_durable: true,
  prefetch: 10,
  heartbeat: 30,
  connection_timeout: 5,
  recovery_attempts: 5
)
```

### Exchange Types

The transport supports different RabbitMQ exchange types:

```ruby
# Topic exchange (default) - supports pattern routing
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  exchange_type: :topic
)

# Direct exchange - exact routing key matching
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  exchange_type: :direct
)

# Fanout exchange - broadcast to all queues  
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  exchange_type: :fanout
)
```

### Circuit Breaker Integration

The transport includes built-in circuit breakers for reliability:

```ruby
# Check circuit breaker status
stats = transport.transport_circuit_stats
puts stats[:transport_publish][:status] # :closed, :open, :half_open

# Reset circuit breakers
transport.reset_transport_circuits!

# Reset specific circuit
transport.reset_transport_circuits!(:transport_publish)
```

### Connection Management

```ruby
# Check connection status
puts transport.connected?

# Graceful disconnect
transport.disconnect

# Reconnect
transport.connect
```

## Architecture Benefits

### Transport-Centric Design

- **Centralized Serialization**: All messages through a transport use the same serializer
- **Pre-Serialization Routing**: Transport extracts routing metadata before serialization
- **Transport Optimization**: Each transport can optimize for its specific capabilities  
- **Simplified Message Classes**: Messages focus on data, not transport concerns

### RabbitMQ-Native Dispatcher

The transport includes a specialized dispatcher that:

- Leverages RabbitMQ's topic exchange pattern matching
- Stores routing patterns per handler for efficient lookup
- Converts RabbitMQ wildcards to regex for flexible matching
- Optimizes message routing using native RabbitMQ capabilities

### Unified Subscription API

- **Consistent Interface**: Same API across all SmartMessage transports
- **Multi-Message Support**: Subscribe to arrays of message classes
- **Regex Patterns**: Subscribe using regular expressions  
- **Fluent API**: Chainable methods for complex conditions
- **Backward Compatible**: Works with existing SmartMessage code

## Error Handling and Reliability

### Automatic Recovery

The transport automatically handles:

- Connection failures and recovery
- Consumer restart after reconnection  
- Circuit breaker fallbacks
- Dead letter queue integration

### Message Acknowledgment

```ruby
# Messages are automatically acknowledged after successful processing
# Failed message processing triggers rejection and potential requeue
```

### Logging

The transport provides comprehensive logging:

```ruby
# Transport logs all major operations:
# - Connection establishment/teardown
# - Message publishing with routing keys
# - Message consumption and processing
# - Error conditions and recovery
```

## Migration from Legacy Architecture

### Constructor Changes

**Old:**
```ruby
transport = SmartMessage::Transport::RabbitMQ.new(host: 'localhost')
```

**New:**
```ruby
serializer = SmartMessage::Serializer::Json.new
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  host: 'localhost'
)
```

### Publishing Changes

**Old:**
```ruby
# Message handled its own serialization
message.publish
```

**New:**
```ruby  
# Transport handles serialization, supports routing options
message.publish(from: 'service_a', to: 'service_b')
```

### Subscription Changes

**Old:**
```ruby
# Message class subscriptions only
OrderMessage.subscribe
OrderMessage.subscribe("MyService.handle_order")
```

**New:**
```ruby
# Transport-centric with multi-class support
transport.subscribe(OrderMessage) { |msg| handle_order(msg) }
transport.subscribe([OrderMessage, PaymentMessage]) { |msg| handle_msg(msg) }
transport.subscribe(/.*Message$/) { |msg| log_message(msg) }
```

## Examples

See the `examples/` directory for complete working examples:

- `enhanced_routing_usage.rb` - Demonstrates new architecture features
- `messages/` - Example message class definitions

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MadBomber/smart_message-transport-rabbitmq.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).