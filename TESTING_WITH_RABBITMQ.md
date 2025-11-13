# Testing with Real RabbitMQ

The test suite for `smart_message-transport-rabbitmq` is designed to run against a **live RabbitMQ server**. This provides more realistic testing of message publishing, routing, and consumption.

## Quick Start

### Option 1: Docker (Recommended)

Start RabbitMQ using Docker:

```bash
# Start RabbitMQ
docker run -d --name rabbitmq-test \
  -p 5672:5672 \
  -p 15672:15672 \
  rabbitmq:3.12-management-alpine

# Wait for RabbitMQ to be ready (about 10 seconds)
sleep 10

# Run tests
bundle exec rake test

# Stop and remove when done
docker stop rabbitmq-test
docker rm rabbitmq-test
```

### Option 2: Docker Compose

Use the included docker-compose file:

```bash
# Start RabbitMQ
docker-compose up -d

# Run tests
bundle exec rake test

# Stop when done
docker-compose down
```

### Option 3: Local RabbitMQ Installation

If you have RabbitMQ installed locally:

```bash
# Start RabbitMQ (method depends on your OS)
# macOS with homebrew:
brew services start rabbitmq

# Linux with systemd:
sudo systemctl start rabbitmq-server

# Run tests
bundle exec rake test
```

## Configuration

The tests use these default RabbitMQ connection settings:

```ruby
host: ENV['RABBITMQ_HOST'] || 'localhost'
port: ENV['RABBITMQ_PORT'] || 5672
username: ENV['RABBITMQ_USERNAME'] || 'guest'
password: ENV['RABBITMQ_PASSWORD'] || 'guest'
vhost: ENV['RABBITMQ_VHOST'] || '/'
```

### Custom Configuration

Override defaults with environment variables:

```bash
# Example: Use a different host
export RABBITMQ_HOST=rabbitmq.example.com
export RABBITMQ_PORT=5673
export RABBITMQ_USERNAME=testuser
export RABBITMQ_PASSWORD=testpass

bundle exec rake test
```

## Test Behavior

### When RabbitMQ is Available

Tests will:
- Connect to the RabbitMQ server
- Create a test exchange (`test_smart_message`)
- Create temporary queues for testing
- Publish and consume real messages
- Clean up all resources after each test

### When RabbitMQ is Not Available

Tests will:
- Detect that RabbitMQ is not running
- Skip all tests gracefully
- Display a message: "RabbitMQ not available at localhost:5672"

Example output:
```
10 tests, 0 assertions, 0 failures, 0 errors, 10 skips
```

## Accessing RabbitMQ Management UI

When using Docker with the management plugin:

1. Open your browser to: http://localhost:15672
2. Login with:
   - Username: `guest`
   - Password: `guest`
3. View exchanges, queues, and messages created by tests

## Test Cleanup

Tests automatically clean up after themselves:

- **Queues**: Deleted after each test
- **Messages**: Purged from queues
- **Connections**: Properly closed

If tests are interrupted, you may need to manually clean up:

```bash
# Using rabbitmqctl
rabbitmqctl list_queues | grep smart_message
rabbitmqctl delete_queue <queue_name>

# Or restart RabbitMQ
docker restart rabbitmq-test
```

## Writing New Tests

### Basic Test Pattern

```ruby
def test_my_feature
  with_test_transport do |transport|
    # Test code here
    # Transport is automatically connected and cleaned up
  end
end
```

### Publishing and Consuming

```ruby
def test_publish_and_consume
  with_test_transport do |transport|
    received_messages = []

    # Subscribe to messages
    transport.subscribe(MyMessage) do |msg|
      received_messages << msg
    end

    # Publish a message
    message = MyMessage.new(data: "test")
    serialized = transport.serializer.encode(message)
    routing_key = "MyMessage.broadcast.anonymous"
    transport.send(:do_publish, 'MyMessage', serialized, routing_key)

    # Wait for message
    wait_for_message(timeout: 2) { received_messages.any? }

    assert_equal 1, received_messages.length
  end
end
```

### Test Helpers Available

```ruby
# Skip if RabbitMQ not available
skip_without_rabbitmq

# Check if RabbitMQ is available
rabbitmq_available? # => true/false

# Create transport (auto-cleanup)
transport = create_test_transport

# Wait for condition
wait_for(timeout: 2) { some_condition }

# Wait for message
wait_for_message(timeout: 2) { received.any? }

# Get queue message count
count = get_published_message_count(transport, "queue_name")

# Purge a queue
purge_queue(transport, "queue_name")
```

## Troubleshooting

### Connection Refused

**Problem:** Tests skip with "Connection refused"

**Solution:** Ensure RabbitMQ is running:
```bash
# Check if RabbitMQ is listening
netstat -an | grep 5672
# or
lsof -i :5672

# Check Docker container
docker ps | grep rabbitmq
docker logs rabbitmq-test
```

### Port Already in Use

**Problem:** Can't start RabbitMQ - port 5672 in use

**Solution:** Stop existing RabbitMQ instance:
```bash
# Find process using port 5672
lsof -ti:5672 | xargs kill

# Or stop Docker container
docker stop rabbitmq-test
```

### Slow Tests

**Problem:** Tests run slowly

**Causes:**
- Network latency to RabbitMQ
- RabbitMQ not fully started
- Too many queues/connections not cleaned up

**Solutions:**
```bash
# Restart RabbitMQ to clear state
docker restart rabbitmq-test

# Increase test timeouts if network is slow
# In test_helper.rb, adjust wait timeouts

# Run specific test files instead of full suite
bundle exec ruby -Ilib:test test/unit/transport/rabbitmq_test.rb
```

### Authentication Failed

**Problem:** Tests fail with authentication error

**Solution:** Check credentials:
```bash
# Default credentials for Docker RabbitMQ
Username: guest
Password: guest

# Verify with:
docker exec rabbitmq-test rabbitmqctl list_users
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      rabbitmq:
        image: rabbitmq:3.12-alpine
        ports:
          - 5672:5672
        options: >-
          --health-cmd "rabbitmq-diagnostics ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Run tests
        run: bundle exec rake test
```

### GitLab CI Example

```yaml
test:
  image: ruby:3.3
  services:
    - rabbitmq:3.12-alpine
  variables:
    RABBITMQ_HOST: rabbitmq
  script:
    - bundle install
    - bundle exec rake test
```

## Performance Testing

For performance tests with high message volumes:

```ruby
def test_high_volume_publishing
  skip "Performance test - run manually" unless ENV['RUN_PERFORMANCE_TESTS']

  with_test_transport do |transport|
    # Publish 10,000 messages
    10_000.times do |i|
      transport.send(:do_publish, 'TestMessage', "{\"id\":#{i}}", "TestMessage.test.api")
    end

    # Verify all published
    assert transport.connected?
  end
end
```

Run with:
```bash
RUN_PERFORMANCE_TESTS=1 bundle exec ruby -Ilib:test test/performance/throughput_test.rb
```

## Best Practices

1. **Always use `with_test_transport`** - Ensures proper cleanup
2. **Use unique exchange names** - Prevents test interference
3. **Wait for async operations** - Use `wait_for_message` helper
4. **Clean up resources** - Let helpers handle it automatically
5. **Skip when unavailable** - Tests should never fail due to missing RabbitMQ
6. **Test realistic scenarios** - Use real message sizes and patterns
7. **Verify both success and failure** - Test error conditions too

## Additional Resources

- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [Bunny Gem Documentation](http://rubybunny.info/)
- [RabbitMQ Docker Image](https://hub.docker.com/_/rabbitmq)
- [RabbitMQ Management Plugin](https://www.rabbitmq.com/management.html)

---

**Last Updated:** 2025-11-13
