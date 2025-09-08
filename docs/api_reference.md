# RabbitMQ Transport API Reference

## SmartMessage::Transport::RabbitMQ

The main transport class that handles RabbitMQ connections and message routing.

### Constructor

```ruby
SmartMessage::Transport::RabbitMQ.new(serializer:, **options)
```

**Parameters:**
- `serializer:` (required) - Message serializer instance (e.g., `SmartMessage::Serializer::Json.new`)
- `**options` - Configuration options (see Configuration Options section)

**Returns:** New RabbitMQ transport instance

**Example:**
```ruby
serializer = SmartMessage::Serializer::Json.new
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  host: 'localhost',
  port: 5672,
  exchange_name: 'my_app'
)
```

### Instance Methods

#### `#connect`

Establishes connection to RabbitMQ broker and sets up exchange.

```ruby
transport.connect
```

**Returns:** `nil`  
**Raises:** `SmartMessage::Transport::RabbitMQ::Error` on connection failure

#### `#disconnect`

Closes connection to RabbitMQ broker and cleans up resources.

```ruby
transport.disconnect
```

**Returns:** `nil`

#### `#connected?`

Checks if transport is connected to RabbitMQ broker.

```ruby
transport.connected?
```

**Returns:** `Boolean` - `true` if connected, `false` otherwise

#### `#publish(message_instance, **routing_options)`

Publishes a message through the transport (called internally by `message.publish`).

```ruby
transport.publish(message_instance, from: 'sender', to: 'recipient')
```

**Parameters:**
- `message_instance` - SmartMessage instance to publish
- `**routing_options` - Routing options hash
  - `from:` (String, optional) - Sender identifier
  - `to:` (String, optional) - Recipient identifier  
  - `transport:` (Transport, optional) - Override transport

**Returns:** `nil`  
**Raises:** Various exceptions on publish failure

#### `#subscribe(message_classes, handler = nil, options = {}, &block)`

Subscribe to one or more message classes with unified API.

```ruby
# Single message class with block
transport.subscribe(OrderMessage) { |msg| handle_order(msg) }

# Multiple message classes  
transport.subscribe([OrderMessage, PaymentMessage], handler_proc)

# With routing filters
transport.subscribe(OrderMessage, nil, { from: 'api_server' }) { |msg| process(msg) }

# Regex pattern matching
transport.subscribe(/.*Message$/) { |msg| log_message(msg) }
```

**Parameters:**
- `message_classes` - Message class(es) to subscribe to:
  - `Class` - Single message class
  - `Array<Class>` - Multiple message classes
  - `Regexp` - Pattern to match class names
  - `String` - Class name string
- `handler` - Handler for messages (optional if block provided):
  - `Proc/Lambda` - Callable handler
  - `Method` - Method object
  - `String` - Method name (e.g., "MyService.handle_message")
  - `nil` - Use block or default process method
- `options` - Routing filters (optional):
  - `from:` (String/Array) - Filter by sender(s)
  - `to:` (String/Array) - Filter by recipient(s)  
  - `broadcast:` (Boolean) - Filter broadcast messages
- `&block` - Block handler (optional)

**Returns:** `nil`

#### `#unsubscribe(message_class, process_method)`

Remove specific handler from message class subscriptions.

```ruby
transport.unsubscribe("OrderMessage", "MyService.handle_order")
```

**Parameters:**
- `message_class` (String) - Message class name
- `process_method` (String) - Handler identifier to remove

**Returns:** `nil`

#### `#unsubscribe!(message_class)`  

Remove all handlers for a message class.

```ruby
transport.unsubscribe!("OrderMessage")
```

**Parameters:**
- `message_class` (String) - Message class name

**Returns:** `nil`

#### `#where`

Entry point for fluent subscription API.

```ruby
transport.where
  .message_class(OrderMessage)
  .from('payment_gateway')
  .to('order_service')  
  .subscribe { |msg| handle_payment_order(msg) }
```

**Returns:** `SmartMessage::FluentSubscriptionBuilder` instance

#### `#subscribers`

Get current subscription registry.

```ruby
subscribers = transport.subscribers
```

**Returns:** `Hash` - Current subscriptions hash

## Legacy Pattern-Based Methods (Backward Compatibility)

### `#subscribe_pattern(pattern, process_method, filter_options = {})`

Subscribe to messages using RabbitMQ routing key patterns.

```ruby
# Subscribe to all OrderMessages  
transport.subscribe_pattern("OrderMessage.*.*", :process)

# Subscribe to all messages to order_service
transport.subscribe_pattern("*.order_service.*", :process)

# Subscribe to emergency messages
transport.subscribe_pattern("emergency.#.*.*", :process)
```

**Parameters:**
- `pattern` (String) - RabbitMQ routing key pattern with wildcards
- `process_method` (Symbol/String) - Handler method  
- `filter_options` (Hash) - Additional filter options

### Convenience Subscription Methods

#### `#subscribe_to_recipient(recipient_id)`

Subscribe to all messages sent to specific recipient.

```ruby
transport.subscribe_to_recipient('order_service')
```

#### `#subscribe_from_sender(sender_id)`

Subscribe to all messages from specific sender.

```ruby  
transport.subscribe_from_sender('payment_gateway')
```

#### `#subscribe_to_type(message_type)`

Subscribe to specific message type regardless of sender/recipient.

```ruby
transport.subscribe_to_type('OrderMessage')
```

#### `#subscribe_to_alerts`

Subscribe to all alert/emergency messages.

```ruby
transport.subscribe_to_alerts
```

#### `#subscribe_to_broadcasts`  

Subscribe to broadcast messages.

```ruby
transport.subscribe_to_broadcasts
```

## Configuration Options

### Connection Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `host` | String | `'localhost'` | RabbitMQ server hostname |
| `port` | Integer | `5672` | RabbitMQ server port |
| `username` | String | `'guest'` | Authentication username |
| `password` | String | `'guest'` | Authentication password |
| `vhost` | String | `'/'` | RabbitMQ virtual host |

### Exchange Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `exchange_name` | String | `'smart_message'` | Exchange name |
| `exchange_type` | Symbol | `:topic` | Exchange type (`:topic`, `:direct`, `:fanout`) |
| `exchange_durable` | Boolean | `true` | Exchange survives server restart |

### Queue Options

| Option | Type | Default | Description |  
|--------|------|---------|-------------|
| `queue_durable` | Boolean | `true` | Queues survive server restart |
| `queue_auto_delete` | Boolean | `false` | Auto-delete unused queues |

### Connection Management

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `heartbeat` | Integer | `30` | Heartbeat interval (seconds) |
| `connection_timeout` | Integer | `5` | Connection timeout (seconds) |
| `recovery_attempts` | Integer | `5` | Max connection recovery attempts |
| `recovery_attempts_exhausted` | Proc | `proc { raise }` | Handler when recovery fails |
| `prefetch` | Integer | `10` | Consumer prefetch count |

## Environment Variables

The transport recognizes these environment variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| `RABBITMQ_HOST` | Server hostname | `localhost` |  
| `RABBITMQ_PORT` | Server port | `5672` |
| `RABBITMQ_USERNAME` | Authentication username | `guest` |
| `RABBITMQ_PASSWORD` | Authentication password | `guest` |
| `RABBITMQ_VHOST` | Virtual host | `/` |
| `RABBITMQ_HEARTBEAT` | Heartbeat interval | `30` |
| `RABBITMQ_CONNECTION_TIMEOUT` | Connection timeout | `5` |
| `RABBITMQ_RECOVERY_ATTEMPTS` | Recovery attempts | `5` |
| `SMART_MESSAGE_EXCHANGE` | Exchange name | `smart_message` |

## Circuit Breaker Methods

### `#transport_circuit_stats`

Get circuit breaker statistics.

```ruby
stats = transport.transport_circuit_stats
puts stats[:transport_publish][:status] # :closed, :open, :half_open
```

**Returns:** `Hash` - Circuit breaker statistics

### `#reset_transport_circuits!(circuit_name = nil)`

Reset circuit breakers.

```ruby
# Reset all circuits
transport.reset_transport_circuits!

# Reset specific circuit  
transport.reset_transport_circuits!(:transport_publish)
```

**Parameters:**
- `circuit_name` (Symbol, optional) - Specific circuit to reset

## RabbitMQDispatcher

Internal dispatcher class optimized for RabbitMQ routing.

### Key Features

- **Pattern Caching**: Routing patterns cached per handler
- **Regex Compilation**: RabbitMQ wildcards converted to regex  
- **Efficient Lookup**: Hash-based handler lookup
- **Native Integration**: Leverages RabbitMQ topic exchange

### Methods

#### `#add(message_class, handler, options = {})`

Add handler with routing patterns.

#### `#drop(message_class, handler_id)`  

Remove specific handler.

#### `#drop_all(message_class)`

Remove all handlers for message class.

#### `#route(message, routing_key = nil)`

Route message to matching handlers.

## Error Classes

### `SmartMessage::Transport::RabbitMQ::Error`

Base error class for RabbitMQ transport errors.

```ruby
begin
  transport.connect
rescue SmartMessage::Transport::RabbitMQ::Error => e
  puts "Transport error: #{e.message}"
end
```

## Usage Patterns

### Basic Setup

```ruby
# 1. Create serializer
serializer = SmartMessage::Serializer::Json.new

# 2. Create transport  
transport = SmartMessage::Transport::RabbitMQ.new(
  serializer: serializer,
  host: 'localhost'
)

# 3. Configure as default
SmartMessage.configure { |config| config.transport = transport }

# 4. Connect
transport.connect
```

### Publishing Messages

```ruby
# Create message
order = OrderMessage.new(order_id: "123", amount: 99.99)

# Simple publish
order.publish

# With routing
order.publish(from: 'api_server', to: 'order_service')
```

### Subscribing to Messages

```ruby
# Single class
transport.subscribe(OrderMessage) { |msg| process_order(msg) }

# Multiple classes
transport.subscribe([OrderMessage, PaymentMessage]) do |msg|
  puts "Processing #{msg.class.name}"
end

# With filters
transport.subscribe(OrderMessage, nil, { from: 'api_server' }) do |msg|
  puts "API order: #{msg.order_id}"
end
```

### Error Handling

```ruby
begin
  order.publish(to: 'order_service')  
rescue SmartMessage::Transport::RabbitMQ::Error => e
  logger.error "Failed to publish: #{e.message}"
  # Handle error (retry, DLQ, etc.)
end
```