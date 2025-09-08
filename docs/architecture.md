# RabbitMQ Transport Architecture

## Overview

The SmartMessage RabbitMQ transport implements a transport-centric architecture that leverages RabbitMQ's advanced routing capabilities while providing a unified subscription API compatible with the broader SmartMessage framework.

## Key Architectural Principles

### 1. Transport-Centric Design

The transport owns the serialization strategy rather than individual message classes:

```ruby
# Transport constructor requires serializer
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: SmartMessage::Serializer::Json.new,
  host: 'localhost'
)
```

**Benefits:**
- Consistent serialization across all messages
- Pre-serialization routing metadata extraction
- Transport-specific optimizations
- Simplified message class responsibilities

### 2. Standardized 3-Component Routing Keys

All routing keys follow the format: `{message_class}.{to_recipient}.{from_sender}`

```
OrderMessage.order_service.api_server
PaymentMessage.billing_service.payment_gateway  
AlertMessage.broadcast.monitoring_service
```

**Wildcard Defaulting:**
- Missing `to`: defaults to "broadcast"
- Missing `from`: defaults to "anonymous"
- Missing both: `OrderMessage.broadcast.anonymous`

### 3. RabbitMQ-Native Dispatcher

The transport includes a specialized dispatcher that leverages RabbitMQ's topic exchange:

```ruby
class RabbitMQDispatcher
  # Stores routing patterns per handler
  def add(message_class, handler, options = {})
    handler_info = {
      handler: handler,
      routing_patterns: build_routing_patterns(message_class, options)
    }
    @subscribers[message_class] << handler_info
  end
  
  # Converts RabbitMQ patterns to regex for matching
  def routing_key_matches?(routing_key, patterns)
    patterns.any? do |pattern|
      regex_pattern = pattern
        .gsub('.', '\.')     # Escape dots
        .gsub('*', '[^.]+')  # * matches one word  
        .gsub('#', '.*')     # # matches zero or more words
      routing_key =~ /^#{regex_pattern}$/
    end
  end
end
```

## Message Flow

### Publishing Flow

1. **Message Creation**: Application creates message instance
2. **Validation**: Message validates itself
3. **Header Updates**: Publication metadata added (timestamp, PID, etc.)
4. **Transport Resolution**: Routing options determine transport to use
5. **Transport Publishing**: Transport handles serialization and routing key generation
6. **RabbitMQ Delivery**: Message published to topic exchange with routing key

```ruby
order = OrderMessage.new(order_id: "123", amount: 99.99)
order.publish(from: 'api_server', to: 'order_service')

# Internally becomes:
# 1. transport.publish(order, from: 'api_server', to: 'order_service')  
# 2. routing_key = "OrderMessage.order_service.api_server"
# 3. serialized_message = serializer.encode(order)
# 4. exchange.publish(serialized_message, routing_key: routing_key)
```

### Subscription Flow

1. **Subscription Registration**: Handler registered with message classes and filters
2. **Queue Creation**: RabbitMQ queue created for message class
3. **Binding Setup**: Queue bound to exchange with routing patterns
4. **Consumer Creation**: Bunny consumer created to handle incoming messages
5. **Message Processing**: Messages routed through dispatcher to handlers

```ruby
transport.subscribe(OrderMessage, nil, { from: 'api_server' }) do |message|
  process_order(message)
end

# Internally becomes:
# 1. Queue: "smart_message.ordermessage" 
# 2. Binding: "OrderMessage.*.api_server"
# 3. Consumer processes matching messages
```

## Advanced Features

### Multi-Message Class Subscriptions

```ruby
# Array of classes
transport.subscribe([OrderMessage, PaymentMessage]) { |msg| handle(msg) }

# Regex pattern matching  
transport.subscribe(/.*Message$/) { |msg| log_message(msg) }
```

### Fluent API Support

```ruby
transport.where
  .message_class(OrderMessage)
  .from('payment_gateway') 
  .to('order_service')
  .subscribe { |msg| handle_payment_order(msg) }
```

### Pattern-Based Subscriptions (Legacy)

For backward compatibility, the transport maintains pattern-based subscription methods:

```ruby
# Subscribe to all messages to a recipient
transport.subscribe_to_recipient('order_service')

# Subscribe to all messages from a sender  
transport.subscribe_from_sender('payment_gateway')

# Subscribe to all alerts
transport.subscribe_to_alerts
```

## RabbitMQ Integration

### Exchange Configuration

```ruby
# Topic exchange (default) - supports wildcard routing
exchange_type: :topic

# Direct exchange - exact routing key matching  
exchange_type: :direct

# Fanout exchange - broadcast to all queues
exchange_type: :fanout
```

### Connection Management

- **Automatic Recovery**: Built-in connection recovery with configurable retry attempts
- **Consumer Restart**: Consumers automatically restart after connection recovery
- **Circuit Breakers**: Integrated circuit breakers for reliability
- **Connection Pooling**: Single connection shared across all operations

### Queue Strategy

- **Message Class Queues**: Each message class gets its own queue
- **Durable Queues**: Queues survive broker restarts (configurable)
- **Manual Acknowledgment**: Messages acknowledged after successful processing
- **Prefetch Limit**: Configurable consumer prefetch for flow control

## Performance Optimizations

### RabbitMQ-Native Features

1. **Topic Exchange Routing**: Leverages RabbitMQ's built-in pattern matching
2. **Queue Binding Optimization**: Efficient binding patterns reduce routing overhead
3. **Consumer Prefetch**: Configurable prefetch prevents consumer overwhelming
4. **Connection Reuse**: Single connection shared across operations

### Dispatcher Optimizations

1. **Pattern Caching**: Routing patterns cached per handler
2. **Regex Compilation**: Patterns compiled to regex once and reused
3. **Handler Lookup**: Efficient handler lookup using hash maps
4. **Early Termination**: Pattern matching short-circuits on first match

## Error Handling

### Circuit Breaker Integration

```ruby
# Publish circuit breaker
circuit(:transport_publish) do
  threshold failures: 5, within: 60.seconds
  reset_after 30.seconds
  fallback { |msg| send_to_dlq(msg) }
end

# Subscribe circuit breaker  
circuit(:transport_subscribe) do
  threshold failures: 10, within: 120.seconds
  reset_after 60.seconds
  fallback { |error| log_subscription_failure(error) }
end
```

### Message Acknowledgment

- **Success**: Message acknowledged and removed from queue
- **Processing Error**: Message rejected and potentially requeued
- **Handler Exception**: Error logged, message rejected
- **Transport Error**: Circuit breaker activated, message sent to DLQ

### Connection Recovery

1. **Connection Loss Detection**: Automatic detection via heartbeat
2. **Reconnection Logic**: Exponential backoff with max retry limit
3. **Consumer Restart**: All consumers restarted after reconnection
4. **Queue Redeclaration**: Queues and bindings recreated automatically

## Configuration Reference

### Constructor Options

```ruby
SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,                    # Required: Message serializer
  host: 'localhost',                         # RabbitMQ host
  port: 5672,                               # RabbitMQ port  
  username: 'guest',                        # Authentication username
  password: 'guest',                        # Authentication password
  vhost: '/',                              # Virtual host
  exchange_name: 'smart_message',          # Exchange name
  exchange_type: :topic,                   # Exchange type
  exchange_durable: true,                  # Exchange durability
  queue_durable: true,                     # Queue durability
  queue_auto_delete: false,                # Queue auto-deletion
  prefetch: 10,                           # Consumer prefetch count
  heartbeat: 30,                          # Connection heartbeat interval
  connection_timeout: 5,                   # Connection timeout
  recovery_attempts: 5,                    # Max recovery attempts
  recovery_attempts_exhausted: proc { raise } # Recovery failure handler
)
```

### Environment Variables

The transport supports configuration via environment variables:

```bash
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest  
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/
RABBITMQ_HEARTBEAT=30
RABBITMQ_CONNECTION_TIMEOUT=5
RABBITMQ_RECOVERY_ATTEMPTS=5
SMART_MESSAGE_EXCHANGE=smart_message
```

## Migration Considerations

### From Message-Centric to Transport-Centric

**Old Approach:**
```ruby
# Message handled serialization
OrderMessage.configure do |config|
  config.serializer = JsonSerializer.new
  config.transport = rabbitmq_transport
end

order.publish
```

**New Approach:**  
```ruby
# Transport handles serialization
transport = RabbitMQ.new(serializer: JsonSerializer.new)
SmartMessage.configure { |config| config.transport = transport }

order.publish(from: 'api', to: 'service')
```

### Subscription API Changes

**Old Approach:**
```ruby
OrderMessage.subscribe
OrderMessage.subscribe("MyService.handle_order")
```

**New Approach:**
```ruby
transport.subscribe(OrderMessage) { |msg| handle_order(msg) }
transport.subscribe([OrderMessage, PaymentMessage]) { |msg| handle_msg(msg) }
```

### Routing Key Format Changes

**Old Format:** Variable components based on message content
**New Format:** Standardized 3-component: `message_class.to.from`

This change provides consistent routing across all transports while maintaining RabbitMQ's advanced pattern matching capabilities.