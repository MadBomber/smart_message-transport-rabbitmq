# Enhanced RabbitMQ Routing Patterns

This document explains the enhanced routing key system that includes sender and recipient UUIDs for powerful message filtering.

## Routing Key Format

```
{namespace}.{message_type}.{from_uuid}.{to_uuid}
```

### Examples:
- `myapp.ordermessage.user123.service456`
- `emergency.firealert.station01.broadcast`
- `system.heartbeat.node789.monitor123`

## Subscription Patterns

### Wildcard Rules
- `*` - matches exactly one word
- `#` - matches zero or more words

### Common Subscription Patterns

#### 1. **Personal Message Filtering**

```ruby
# All messages TO me (regardless of sender or type)
"#.*.my_uuid"

# All messages FROM a specific sender TO me  
"#.sender_uuid.my_uuid"

# All messages FROM me (regardless of recipient or type)
"#.my_uuid.*"
```

#### 2. **Message Type Filtering**

```ruby
# All alerts regardless of sender/recipient
"#.alert.*.*"

# All order messages regardless of routing
"*.ordermessage.*.*"

# All emergency messages (any subtype)
"emergency.#.*.*"
```

#### 3. **Broadcast/System Messages**

```ruby
# All broadcast messages
"#.*.broadcast"

# System broadcasts only
"system.*.*.broadcast"

# Alerts broadcast to everyone
"#.alert.*.broadcast"
```

#### 4. **Namespace-based Filtering**

```ruby
# Everything in emergency namespace
"emergency.#"

# Emergency messages to me only
"emergency.#.*.my_uuid"

# All messages in myapp namespace from specific user
"myapp.#.user123.*"
```

#### 5. **Complex Combined Patterns**

```ruby
# Orders from vendors to our system
"commerce.ordermessage.vendor_*.system_*"

# All critical alerts from monitoring systems
"monitoring.critical.*.*"

# Heartbeats between specific service pairs
"system.heartbeat.service_a.service_b"
```

## Usage Examples

### Basic Subscription

```ruby
transport = SmartMessage::Transport::RabbitMQEnhanced.new

# Subscribe to all messages for me
transport.subscribe_pattern("#.*.my_uuid_123", :process)

# Subscribe to all order messages
transport.subscribe_pattern("*.ordermessage.*.*", :process)

# Subscribe to emergency broadcasts
transport.subscribe_pattern("emergency.#.*.broadcast", :process)
```

### Convenience Methods

```ruby
# All messages to me
transport.subscribe_to_recipient('my_uuid_123')

# All messages from a service
transport.subscribe_from_sender('payment_service_456')

# All alerts regardless of routing
transport.subscribe_to_alerts

# All broadcast messages
transport.subscribe_to_broadcasts
```

### Fluent API

```ruby
# Complex filtering with fluent interface
transport.where
  .from('payment_service')
  .to('order_processor')
  .type('payment_confirmation')
  .subscribe

# Monitor all emergency traffic
transport.where
  .namespace('emergency')
  .subscribe
```

## Real-World Scenarios

### 1. **Microservice Communication**

```ruby
# Order service listens for payments directed to it
transport.subscribe_pattern("payment.#.*.order_service", :process)

# Payment service listens for order requests from any source
transport.subscribe_pattern("commerce.payment_request.*.payment_service", :process)
```

### 2. **Monitoring & Alerting**

```ruby
# Monitoring service gets all system alerts
transport.subscribe_pattern("#.alert.*.*", :process)

# Security service gets all security-related messages
transport.subscribe_pattern("security.#.*.*", :process)

# Dashboard gets all broadcasts for display
transport.subscribe_pattern("#.*.dashboard", :process)
```

### 3. **Multi-tenant Applications**

```ruby
# Tenant-specific message filtering
transport.subscribe_pattern("tenant_abc.#.*.*", :process)

# Admin gets messages from all tenants
transport.subscribe_pattern("tenant_*.#.*.admin", :process)
```

### 4. **Load Balancing Scenarios**

```ruby
# Multiple workers share the same pattern (RabbitMQ distributes via queue)
worker_instances.each do |worker|
  worker.subscribe_pattern("jobs.#.*.*", :process_job)
end
```

### 5. **Development/Testing**

```ruby
# Debug mode: see all traffic
transport.subscribe_pattern("#.*.*.*", :log_message) if ENV['DEBUG']

# Test environment: isolate test messages
transport.subscribe_pattern("test.#.*.*", :process) if ENV['RACK_ENV'] == 'test'
```

## Benefits of Enhanced Routing

1. **Fine-grained Control**: Subscribe only to messages relevant to your service
2. **Reduced Processing**: Less CPU/memory usage from irrelevant messages  
3. **Security**: Services only see messages intended for them
4. **Debugging**: Easy to monitor specific communication patterns
5. **Scalability**: Efficient message distribution across services
6. **Flexibility**: Change routing patterns without code changes

## Performance Considerations

- **Queue Management**: Each unique pattern creates a separate queue
- **Binding Efficiency**: More specific patterns = fewer irrelevant messages
- **Pattern Complexity**: Very complex patterns may impact routing performance
- **Memory Usage**: More patterns = more queues = more memory

## Migration Strategy

To migrate from simple routing keys to enhanced ones:

1. **Dual Binding**: Temporarily bind queues to both old and new patterns
2. **Header Fallback**: Check headers when routing keys aren't enhanced
3. **Gradual Rollout**: Migrate services one at a time
4. **Default Values**: Use 'anonymous'/'broadcast' for missing from/to values

```ruby
# Backwards compatible subscription
transport.subscribe("OrderMessage", :process)           # Old way
transport.subscribe_pattern("*.ordermessage.*.*", :process)  # New way (same effect)
```