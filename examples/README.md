# Enhanced RabbitMQ Transport Examples

This directory contains examples demonstrating the enhanced routing capabilities of the `sm-transport-rabbitmq` gem, which extends the SmartMessage framework with RabbitMQ-based message transport and advanced routing patterns.

## Overview

The `enhanced_routing_usage.rb` example demonstrates **pattern-based subscriptions** for message routing, which is different from the typical SmartMessage handler-based subscriptions you might be familiar with.

## Two Types of Message Handling

### 1. Traditional Handler-Based Subscriptions (SmartMessage Default)

```ruby
# Traditional approach - sets up a message handler
AlertMessage.subscribe do |message|
  puts "Received alert: #{message.severity} - #{message.message}"
end
```

This creates a **message handler** that processes specific message types when they arrive.

### 2. Pattern-Based Subscriptions (Enhanced RabbitMQ Transport)

```ruby
# Enhanced approach - sets up routing pattern matching
transport.subscribe_pattern("#.*.user_123", :process)
transport.subscribe_to_recipient("order_service")
transport.subscribe_from_sender("payment_gateway")
```

This creates **routing subscriptions** that filter messages based on their routing keys, but still relies on the traditional message handlers for actual processing.

## How the Enhanced Routing Works

### Message Flow Architecture

1. **Message Publishing**: When a message is published, the transport creates an enhanced routing key:
   ```
   Format: {namespace}.{message_type}.{from_uuid}.{to_uuid}
   Example: ordermessage.api_server.order_service
   ```

2. **Pattern Subscription**: The `subscribe_pattern()` method creates RabbitMQ queue bindings that match specific routing patterns:
   ```ruby
   transport.subscribe_pattern("#.*.order_service", :process)
   # Matches any message TO order_service, regardless of sender or type
   ```

3. **Message Routing**: When a matching message arrives, the transport:
   - Extracts the message class from the routing key or headers
   - Looks for a registered handler in `@dispatcher.subscribers[message_class]`
   - Calls the handler if found, or logs "No handler" if not found

4. **Handler Registration**: For messages to actually be processed, you still need traditional message handlers:
   ```ruby
   OrderMessage.subscribe do |message|
     message.process  # This is what actually handles the message
   end
   ```

## The Current Example Limitation

The current `enhanced_routing_usage.rb` example demonstrates the **routing subscription setup** but has a limitation with SmartMessage's transport validation that prevents the traditional `.subscribe` handler registration from working in this context. 

**Note**: This appears to be a SmartMessage framework limitation where the transport validation doesn't recognize the RabbitMQ transport as properly configured, even when it is. The enhanced routing and message publishing work correctly, but the traditional handler registration requires further investigation.

## Complete Workflow Example

Here's how a complete setup would look:

```ruby
# 1. Set up enhanced transport
transport = SmartMessage::Transport::RabbitMQ.new(...)

# 2. Configure SmartMessage with the transport
SmartMessage.configure do |config|
  config.transport = transport
  config.serializer = SmartMessage::Serializer::Json.new
end

# 3. Set up traditional message handlers (MISSING in current example)
OrderMessage.subscribe do |message|
  puts "Processing order #{message.order_id} for #{message.customer_id}"
  # Business logic here
end

AlertMessage.subscribe do |message|
  puts "ALERT: #{message.severity} - #{message.message}"
  # Alert handling logic here
end

# 4. Set up enhanced routing patterns
transport.subscribe_to_recipient("order_service")      # Route TO order_service
transport.subscribe_from_sender("payment_gateway")     # Route FROM payment_gateway
transport.subscribe_to_type("alert")                   # Route alert messages

# 5. Publish messages (they will be routed AND processed)
order = OrderMessage.new(from: 'api_server', to: 'order_service', ...)
order.publish  # Will match routing pattern AND trigger handler
```

## Key Benefits of Enhanced Routing

1. **Fine-grained Filtering**: Subscribe to specific sender/recipient combinations
2. **Namespace Isolation**: Separate messages by application domain
3. **Broadcasting**: Send messages to multiple recipients efficiently
4. **Monitoring**: Subscribe to all traffic between specific services
5. **Emergency Routing**: Priority routing for critical messages

## Routing Pattern Examples

| Pattern | Description | Example Use Case |
|---------|-------------|------------------|
| `#.*.order_service` | All messages TO order_service | Service monitoring |
| `#.payment_gateway.*` | All messages FROM payment_gateway | Audit logging |
| `emergency.#.*.*` | All emergency messages | Alert systems |
| `*.ordermessage.*.*` | All order messages | Order processing |
| `#.*.broadcast` | All broadcast messages | System announcements |

## Running the Example

```bash
# Start RabbitMQ (if not running)
brew services start rabbitmq

# Run the example
./enhanced_routing_usage.rb
```

The current example sets up routing subscriptions and publishes messages, but without message handlers, the messages will be routed but not processed (you'll see "No handler" debug messages).

## Message Handlers vs Message Subscriptions

In the SmartMessage framework with RabbitMQ transport, there are two different but related concepts for handling incoming messages:

### 1. Message Handlers (Traditional SmartMessage Pattern)
Message handlers are the **business logic methods** defined within message classes that process the message content:

```ruby
class OrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :customer_id, required: true
  property :amount, required: true

  def process  # <-- This is a message handler
    puts "Processing order #{order_id} for customer #{customer_id}: $#{amount}"
    # Business logic here: validate order, update database, send notifications, etc.
  end
end
```

### 2. Message Subscriptions (Transport-Level Routing)
Message subscriptions are the **routing mechanisms** that determine which messages get delivered to which consumers:

```ruby
# Traditional SmartMessage subscription (class-level)
OrderMessage.subscribe(:process)  # Subscribe to OrderMessage and call the 'process' method

# Enhanced RabbitMQ pattern subscriptions (transport-level)
transport.subscribe_to_recipient('order_service')     # All messages TO order_service
transport.subscribe_from_sender('payment_gateway')    # All messages FROM payment_gateway
transport.subscribe_pattern("#.*.user_123", :process) # All messages for user_123
```

### The Relationship

#### Traditional SmartMessage Flow:
1. **Subscription**: `OrderMessage.subscribe(:process)` tells the transport "deliver all OrderMessage instances to the `process` method"
2. **Publication**: When someone publishes an OrderMessage, the transport routes it based on message class
3. **Delivery**: The transport automatically calls `message_instance.process` when an OrderMessage arrives
4. **Handler Execution**: The business logic in the `process` method runs

#### Enhanced RabbitMQ Pattern Flow:
1. **Pattern Subscription**: `transport.subscribe_pattern("#.*.order_service", :process)` tells RabbitMQ "deliver all messages with routing keys ending in 'order_service'"
2. **Publication**: Messages are published with enhanced routing keys like `ordermessage.api_server.order_service`
3. **Pattern Matching**: RabbitMQ's topic exchange matches the routing key against the pattern
4. **Message Processing**: The transport extracts the message class and simulates calling the handler

### Key Differences

| Aspect | Traditional Subscriptions | Pattern Subscriptions |
|--------|--------------------------|----------------------|
| **Scope** | Message class specific | Routing pattern based |
| **Flexibility** | Limited to message types | Can cross message types |
| **Routing** | Class name based | Enhanced 4-part keys |
| **Use Case** | Standard message processing | Advanced routing scenarios |

### Example Scenario

```ruby
# You can have both working together:

# 1. Traditional subscription for specific message processing
OrderMessage.subscribe(:process)

# 2. Pattern subscription for monitoring all order-related traffic
transport.subscribe_pattern("*.ordermessage.*.*", :audit)

# 3. Pattern subscription for emergency alerts regardless of message type  
transport.subscribe_to_alerts  # Subscribes to emergency.*, *.alert.*, etc.
```

### In Our Demo

The demo shows **pattern subscriptions** working with **simulated handlers**:

- **Subscriptions** route messages based on enhanced patterns (`#.*.order_service`, `emergency.#.*.*`)
- **Handlers** are simulated in the transport layer, extracting payload data and calling appropriate processing logic
- This demonstrates the routing capabilities while showing the business logic that would normally be in message class `process` methods

The relationship is: **Subscriptions determine routing** (which messages get delivered where), while **Handlers determine processing** (what happens when a message arrives). Pattern subscriptions provide more flexible routing than traditional class-based subscriptions, enabling complex messaging patterns like service-to-service communication, broadcast messages, and emergency alerting systems.

## Next Steps

To see complete message processing, you would need to add message handler registrations before running the routing patterns. The handlers define what actually happens when messages arrive, while the routing patterns define which messages get delivered to your application.