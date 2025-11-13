# Comprehensive Test Plan
## SmartMessage::Transport::RabbitMQ

**Version:** 1.0
**Date:** 2025-11-13
**Framework:** Minitest 5.x

---

## Table of Contents

1. [Testing Philosophy](#testing-philosophy)
2. [Test Structure](#test-structure)
3. [Test Categories](#test-categories)
4. [Test Coverage Goals](#test-coverage-goals)
5. [Test Environment Setup](#test-environment-setup)
6. [Test Data and Fixtures](#test-data-and-fixtures)
7. [Testing Patterns](#testing-patterns)
8. [Running Tests](#running-tests)
9. [Continuous Integration](#continuous-integration)

---

## Testing Philosophy

### Core Principles

1. **Fast Feedback** - Unit tests should run in milliseconds
2. **Isolation** - Tests should not depend on external services by default
3. **Clarity** - Test names should describe behavior, not implementation
4. **Coverage** - Aim for 90%+ code coverage with meaningful tests
5. **Maintainability** - Tests should be easy to understand and update

### Test Pyramid

```
           /\
          /  \
         / E2E\        10% - End-to-end acceptance tests
        /------\
       /        \
      /Integration\    20% - Integration tests (mocked RabbitMQ)
     /------------\
    /              \
   /  Unit Tests   \  70% - Fast, isolated unit tests
  /________________\
```

---

## Test Structure

### Directory Layout

```
test/
├── test_helper.rb                              # Main test configuration
├── support/
│   ├── mock_rabbitmq.rb                       # RabbitMQ mocks
│   ├── test_messages.rb                       # Message class fixtures
│   ├── test_helpers.rb                        # Helper methods
│   ├── assertions.rb                          # Custom assertions
│   └── docker_helpers.rb                      # Docker test environment
├── unit/
│   ├── transport/
│   │   ├── test_rabbitmq.rb                  # Main transport class
│   │   ├── test_rabbitmq_enhanced.rb         # Enhanced transport
│   │   ├── test_connection_manager.rb         # Connection management
│   │   ├── test_publisher.rb                  # Publishing logic
│   │   ├── test_subscriber.rb                 # Subscription logic
│   │   ├── test_circuit_breaker.rb            # Circuit breaker
│   │   ├── test_dead_letter_queue.rb          # DLQ handling
│   │   └── test_metrics.rb                    # Metrics collection
│   ├── dispatchers/
│   │   └── test_rabbitmq_dispatcher.rb        # Message dispatcher
│   └── helpers/
│       ├── test_routing_key_builder.rb         # Routing keys
│       ├── test_sanitization.rb               # Input sanitization
│       └── test_pattern_matcher.rb            # Pattern matching
├── integration/
│   ├── test_publish_subscribe.rb              # Basic pub/sub
│   ├── test_pattern_routing.rb                # Pattern-based routing
│   ├── test_multi_subscriber.rb               # Multiple subscribers
│   ├── test_connection_recovery.rb            # Recovery scenarios
│   ├── test_error_handling.rb                 # Error scenarios
│   └── test_enhanced_features.rb              # Enhanced transport
├── performance/
│   ├── test_throughput.rb                     # Message throughput
│   ├── test_latency.rb                        # Latency measurements
│   ├── test_memory.rb                         # Memory usage
│   └── benchmarks/
│       ├── publish_benchmark.rb               # Publishing benchmarks
│       └── consume_benchmark.rb               # Consumption benchmarks
├── acceptance/
│   ├── test_basic_workflows.rb                # Basic scenarios
│   ├── test_advanced_workflows.rb             # Advanced scenarios
│   └── test_real_rabbitmq.rb                  # Real RabbitMQ tests
└── fixtures/
    ├── messages/
    │   ├── order_message.rb
    │   ├── payment_message.rb
    │   └── alert_message.rb
    └── config/
        └── test_config.yml
```

---

## Test Categories

### 1. Unit Tests (70% of test suite)

**Purpose:** Test individual components in isolation

**Characteristics:**
- Fast (< 1ms per test)
- No external dependencies
- Mocked collaborators
- Focus on single responsibility

**Coverage Areas:**

#### Core Transport Tests
```ruby
# test/unit/transport/test_rabbitmq.rb
- initialization with required parameters
- default configuration values
- environment variable overrides
- connection lifecycle (connect/disconnect)
- publishing message flow
- subscription registration
- routing key generation
- sanitization methods
- error handling
```

#### Dispatcher Tests
```ruby
# test/unit/dispatchers/test_rabbitmq_dispatcher.rb
- handler registration
- pattern matching (*, #)
- routing key matching logic
- handler execution
- multiple handler support
- error propagation
- handler removal
```

#### Circuit Breaker Tests
```ruby
# test/unit/transport/test_circuit_breaker.rb
- state transitions (closed -> open -> half_open)
- failure threshold counting
- timeout and reset logic
- fallback execution
- statistics tracking
- manual circuit control
```

#### Routing Tests
```ruby
# test/unit/helpers/test_routing_key_builder.rb
- standard routing key format
- component sanitization
- wildcard defaulting
- pattern compilation
- edge cases (nil, empty, special chars)
```

### 2. Integration Tests (20% of test suite)

**Purpose:** Test components working together

**Characteristics:**
- Moderate speed (< 100ms per test)
- Mocked external services
- Multiple components interact
- Realistic scenarios

**Coverage Areas:**

#### Publish-Subscribe Flow
```ruby
# test/integration/test_publish_subscribe.rb
- publish and receive single message
- publish multiple messages
- multiple subscribers
- message ordering
- acknowledgment flow
```

#### Pattern Routing
```ruby
# test/integration/test_pattern_routing.rb
- topic exchange routing
- wildcard patterns (* and #)
- complex routing scenarios
- routing filters (from/to)
- broadcast messages
```

#### Connection Recovery
```ruby
# test/integration/test_connection_recovery.rb
- connection loss detection
- automatic reconnection
- consumer restart
- message replay
- state preservation
```

#### Error Handling
```ruby
# test/integration/test_error_handling.rb
- publish failures
- subscription failures
- circuit breaker activation
- dead letter queue routing
- retry mechanisms
```

### 3. Performance Tests (5% of test suite)

**Purpose:** Measure performance characteristics

**Characteristics:**
- Slower (seconds to minutes)
- Measure throughput and latency
- Monitor resource usage
- Establish baselines

**Test Scenarios:**

```ruby
# test/performance/test_throughput.rb
def test_publish_throughput
  # Measure messages/second publishing
  # Target: > 1000 msg/sec on commodity hardware
end

def test_consume_throughput
  # Measure messages/second consumption
  # Target: > 500 msg/sec per consumer
end
```

### 4. Acceptance Tests (5% of test suite)

**Purpose:** Validate complete user scenarios

**Characteristics:**
- Slow (requires Docker/RabbitMQ)
- Full stack testing
- Real RabbitMQ instance
- Production-like scenarios

**Test Scenarios:**

```ruby
# test/acceptance/test_basic_workflows.rb
def test_microservice_communication
  # Setup: Multiple services communicating
  # Exercise: Send requests and responses
  # Verify: All services receive correct messages
end

def test_error_recovery
  # Setup: Services with RabbitMQ
  # Exercise: Kill RabbitMQ, restart it
  # Verify: Services reconnect and resume
end
```

---

## Test Coverage Goals

### Overall Goals

| Component | Target Coverage | Priority |
|-----------|----------------|----------|
| Core Transport | 95% | Critical |
| RabbitMQ Dispatcher | 95% | Critical |
| Connection Manager | 90% | High |
| Circuit Breaker | 95% | High |
| Dead Letter Queue | 90% | High |
| Routing Helpers | 95% | High |
| Enhanced Transport | 85% | Medium |
| Metrics | 80% | Medium |
| **Overall** | **92%** | **Critical** |

### Coverage by Test Type

| Test Type | Lines | Methods | Branches |
|-----------|-------|---------|----------|
| Unit | 85% | 90% | 80% |
| Integration | 5% | 5% | 10% |
| Performance | 2% | 2% | 3% |
| Acceptance | 3% | 3% | 7% |

### Critical Path Coverage

**Must have 100% coverage:**
- Message publishing flow
- Message subscription flow
- Routing key generation
- Error handling paths
- Connection management

---

## Test Environment Setup

### Local Development

```ruby
# test/test_helper.rb

require 'minitest/autorun'
require 'minitest/reporters'
require 'simplecov'

# Configure SimpleCov for coverage
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'

  add_group 'Core', 'lib/smart_message/transport/rabbitmq.rb'
  add_group 'Dispatcher', 'lib/smart_message/transport/rabbitmq_dispatcher.rb'
  add_group 'Helpers', 'lib/smart_message/transport/rabbitmq/helpers'

  minimum_coverage 90
  minimum_coverage_by_file 80
end

# Configure Minitest reporters
Minitest::Reporters.use! [
  Minitest::Reporters::DefaultReporter.new(color: true),
  Minitest::Reporters::HtmlReporter.new
]

# Load support files
Dir[File.join(__dir__, 'support/**/*.rb')].each { |f| require f }
```

### Docker Test Environment

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: test
      RABBITMQ_DEFAULT_PASS: test
      RABBITMQ_DEFAULT_VHOST: test
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "ping"]
      interval: 5s
      timeout: 10s
      retries: 5

  test-runner:
    build: .
    depends_on:
      rabbitmq:
        condition: service_healthy
    environment:
      RABBITMQ_HOST: rabbitmq
      RABBITMQ_PORT: 5672
      RABBITMQ_USERNAME: test
      RABBITMQ_PASSWORD: test
      RABBITMQ_VHOST: test
    volumes:
      - .:/app
    command: bundle exec rake test:acceptance
```

### CI Environment

```yaml
# .github/workflows/test.yml
name: Test Suite

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

    strategy:
      matrix:
        ruby: ['3.2', '3.3']

    steps:
      - uses: actions/checkout@v3

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true

      - name: Run tests
        run: bundle exec rake test
        env:
          RABBITMQ_HOST: localhost

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/.resultset.json
```

---

## Test Data and Fixtures

### Message Fixtures

```ruby
# test/fixtures/messages/order_message.rb
module TestFixtures
  module Messages
    class OrderMessage
      attr_accessor :order_id, :customer_id, :amount, :items

      def initialize(**attrs)
        attrs.each { |k, v| send("#{k}=", v) }
      end

      def self.to_s
        'OrderMessage'
      end

      def class
        OrderMessage
      end
    end

    class PaymentMessage
      attr_accessor :payment_id, :order_id, :status, :amount

      def initialize(**attrs)
        attrs.each { |k, v| send("#{k}=", v) }
      end

      def self.to_s
        'PaymentMessage'
      end

      def class
        PaymentMessage
      end
    end

    class AlertMessage
      attr_accessor :severity, :message, :service, :timestamp

      def initialize(**attrs)
        attrs.each { |k, v| send("#{k}=", v) }
      end

      def self.to_s
        'AlertMessage'
      end

      def class
        AlertMessage
      end
    end
  end
end
```

### Mock Objects

```ruby
# test/support/mock_rabbitmq.rb
module MockRabbitMQ
  class MockConnection
    attr_reader :connected

    def initialize
      @connected = false
      @channels = []
    end

    def start
      @connected = true
    end

    def close
      @connected = false
      @channels.each(&:close)
    end

    def connected?
      @connected
    end

    def create_channel
      channel = MockChannel.new(self)
      @channels << channel
      channel
    end
  end

  class MockChannel
    attr_reader :open, :prefetch_count

    def initialize(connection)
      @connection = connection
      @open = true
      @exchanges = {}
      @queues = {}
    end

    def open?
      @open
    end

    def close
      @open = false
    end

    def prefetch(count)
      @prefetch_count = count
    end

    def exchange(name, type:, durable:)
      @exchanges[name] ||= MockExchange.new(name, type, durable)
    end

    def queue(name, options = {})
      @queues[name] ||= MockQueue.new(name, options)
    end

    def ack(delivery_tag)
      # Mock acknowledgment
    end

    def reject(delivery_tag, requeue)
      # Mock rejection
    end
  end

  class MockExchange
    attr_reader :name, :type, :durable, :published_messages

    def initialize(name, type, durable)
      @name = name
      @type = type
      @durable = durable
      @published_messages = []
    end

    def publish(payload, routing_key:, **options)
      @published_messages << {
        payload: payload,
        routing_key: routing_key,
        options: options
      }
    end
  end

  class MockQueue
    attr_reader :name, :options, :bindings, :consumers

    def initialize(name, options)
      @name = name
      @options = options
      @bindings = []
      @consumers = []
    end

    def bind(exchange, routing_key:)
      @bindings << { exchange: exchange, routing_key: routing_key }
    end

    def subscribe(manual_ack:, block:, &handler)
      consumer = MockConsumer.new(self, handler)
      @consumers << consumer
      consumer
    end
  end

  class MockConsumer
    attr_reader :queue, :handler

    def initialize(queue, handler)
      @queue = queue
      @handler = handler
      @cancelled = false
    end

    def cancel
      @cancelled = true
    end

    def cancelled?
      @cancelled
    end
  end
end
```

### Test Helpers

```ruby
# test/support/test_helpers.rb
module TestHelpers
  def create_test_transport(**options)
    defaults = {
      serializer: MockSerializer.new,
      host: 'localhost',
      port: 5672,
      exchange_name: 'test_exchange'
    }

    transport = SmartMessage::Transport::RabbitMQ.new(
      **defaults.merge(options)
    )

    # Replace connection with mock
    mock_connection = MockRabbitMQ::MockConnection.new
    mock_channel = mock_connection.create_channel
    mock_exchange = mock_channel.exchange(
      defaults[:exchange_name],
      type: :topic,
      durable: true
    )

    transport.instance_variable_set(:@connection, mock_connection)
    transport.instance_variable_set(:@channel, mock_channel)
    transport.instance_variable_set(:@exchange, mock_exchange)

    transport
  end

  def with_test_connection(**options, &block)
    transport = create_test_transport(**options)
    yield transport
  ensure
    transport.disconnect if transport
  end

  def wait_for_message(timeout: 1, &block)
    Timeout.timeout(timeout) do
      loop do
        result = yield
        return result if result
        sleep 0.01
      end
    end
  rescue Timeout::Error
    flunk "Condition not met within #{timeout} seconds"
  end

  def assert_published(transport, routing_key)
    exchange = transport.instance_variable_get(:@exchange)
    published = exchange.published_messages.any? do |msg|
      msg[:routing_key] == routing_key
    end
    assert published, "Expected message with routing key #{routing_key} to be published"
  end

  def refute_published(transport, routing_key)
    exchange = transport.instance_variable_get(:@exchange)
    published = exchange.published_messages.any? do |msg|
      msg[:routing_key] == routing_key
    end
    refute published, "Expected no message with routing key #{routing_key}"
  end
end
```

---

## Testing Patterns

### 1. Arrange-Act-Assert Pattern

```ruby
def test_publish_with_routing_options
  # Arrange
  transport = create_test_transport
  message = TestMessage.new(data: 'test')

  # Act
  transport.publish(message, from: 'api', to: 'service')

  # Assert
  assert_published(transport, 'TestMessage.service.api')
end
```

### 2. Given-When-Then Pattern

```ruby
def test_circuit_breaker_opens_after_failures
  # Given
  circuit_breaker = CircuitBreaker.new(threshold: 3)

  # When
  3.times { circuit_breaker.record_failure }

  # Then
  assert_equal :open, circuit_breaker.state
end
```

### 3. Testing Error Conditions

```ruby
def test_publish_raises_error_when_not_connected
  transport = create_test_transport
  transport.instance_variable_set(:@connection, nil)

  message = TestMessage.new(data: 'test')

  assert_raises(SmartMessage::Transport::RabbitMQ::ConnectionError) do
    transport.publish(message)
  end
end
```

### 4. Testing Callbacks and Blocks

```ruby
def test_subscribe_executes_handler_block
  transport = create_test_transport
  received_messages = []

  transport.subscribe(TestMessage) do |msg|
    received_messages << msg
  end

  # Simulate message reception
  transport.send(:receive, 'TestMessage', '{"data":"test"}')

  assert_equal 1, received_messages.length
end
```

### 5. Testing Async Behavior

```ruby
def test_async_message_processing
  transport = create_test_transport
  processed = Queue.new

  transport.subscribe(TestMessage) do |msg|
    processed << msg
  end

  # Publish in separate thread
  Thread.new do
    message = TestMessage.new(data: 'test')
    transport.publish(message)
  end

  # Wait for processing
  received = wait_for_message(timeout: 2) do
    processed.pop(true) rescue nil
  end

  assert_equal 'test', received.data
end
```

---

## Running Tests

### Basic Commands

```bash
# Run all tests
bundle exec rake test

# Run specific test file
bundle exec ruby test/unit/transport/test_rabbitmq.rb

# Run specific test method
bundle exec ruby test/unit/transport/test_rabbitmq.rb -n test_initialization

# Run with verbose output
bundle exec rake test TESTOPTS="--verbose"

# Run with seed for reproducibility
bundle exec rake test TESTOPTS="--seed=12345"
```

### Test Categories

```bash
# Run only unit tests
bundle exec rake test:unit

# Run only integration tests
bundle exec rake test:integration

# Run only performance tests
bundle exec rake test:performance

# Run only acceptance tests
bundle exec rake test:acceptance
```

### Coverage Reports

```bash
# Generate coverage report
bundle exec rake test:coverage

# View HTML coverage report
open coverage/index.html

# Check coverage threshold
bundle exec rake test:coverage:check
```

### Docker-based Tests

```bash
# Start RabbitMQ and run tests
docker-compose -f docker-compose.test.yml up --abort-on-container-exit

# Run acceptance tests only
docker-compose -f docker-compose.test.yml run test-runner bundle exec rake test:acceptance

# Clean up
docker-compose -f docker-compose.test.yml down -v
```

---

## Continuous Integration

### Rake Tasks

```ruby
# Rakefile additions

require 'rake/testtask'

namespace :test do
  desc 'Run unit tests'
  Rake::TestTask.new(:unit) do |t|
    t.libs << 'test'
    t.test_files = FileList['test/unit/**/*_test.rb']
    t.verbose = true
  end

  desc 'Run integration tests'
  Rake::TestTask.new(:integration) do |t|
    t.libs << 'test'
    t.test_files = FileList['test/integration/**/*_test.rb']
    t.verbose = true
  end

  desc 'Run performance tests'
  task :performance do
    require_relative 'test/performance/run_suite'
  end

  desc 'Run acceptance tests'
  Rake::TestTask.new(:acceptance) do |t|
    t.libs << 'test'
    t.test_files = FileList['test/acceptance/**/*_test.rb']
    t.verbose = true
  end

  desc 'Run all tests with coverage'
  task :coverage do
    ENV['COVERAGE'] = 'true'
    Rake::Task['test'].invoke
  end

  namespace :coverage do
    desc 'Check coverage threshold'
    task :check do
      require 'simplecov'
      require 'json'

      result = JSON.parse(File.read('coverage/.last_run.json'))
      coverage = result['result']['line']

      if coverage < 90
        abort "Coverage #{coverage}% is below threshold of 90%"
      else
        puts "Coverage #{coverage}% meets threshold"
      end
    end
  end
end

task :default => ['test:unit', 'test:integration']
```

### Pre-commit Hooks

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running tests before commit..."

# Run unit tests (fast)
bundle exec rake test:unit

if [ $? -ne 0 ]; then
  echo "Unit tests failed. Commit aborted."
  exit 1
fi

# Run Rubocop
bundle exec rubocop

if [ $? -ne 0 ]; then
  echo "Rubocop violations found. Commit aborted."
  exit 1
fi

echo "All checks passed!"
exit 0
```

---

## Best Practices

### 1. Test Naming

```ruby
# Good: Descriptive test names
def test_publish_includes_routing_key_in_headers
def test_subscribe_with_array_of_message_classes
def test_circuit_breaker_opens_after_threshold_failures

# Bad: Vague test names
def test_publish
def test_subscribe
def test_circuit_breaker
```

### 2. Test Independence

```ruby
# Good: Each test is independent
def test_scenario_a
  transport = create_test_transport
  # Test scenario A
end

def test_scenario_b
  transport = create_test_transport
  # Test scenario B
end

# Bad: Tests depend on each other
def test_scenario_a
  @transport = create_test_transport
  # Test scenario A
end

def test_scenario_b
  # Assumes @transport from scenario_a
end
```

### 3. Explicit Assertions

```ruby
# Good: Clear what is being tested
assert_equal 'OrderMessage.service.api', routing_key
assert_includes published_messages, expected_message
refute_nil transport.connection

# Bad: Unclear assertions
assert routing_key
assert messages
refute transport_var
```

### 4. Test Data

```ruby
# Good: Explicit test data
message = OrderMessage.new(
  order_id: 'ORD-123',
  amount: 99.99,
  customer_id: 'CUST-456'
)

# Bad: Magic values
message = OrderMessage.new(
  order_id: 'abc',
  amount: 1,
  customer_id: 'xyz'
)
```

---

## Appendix

### A. Useful Minitest Features

```ruby
# Skipping tests
skip "Not implemented yet"
skip_if !rabbitmq_available?, "RabbitMQ not available"

# Focused tests (run only this test)
focus
def test_important_feature
end

# Assertions
assert_equal expected, actual
assert_nil value
assert_raises(ErrorClass) { code }
assert_match /pattern/, string
assert_in_delta expected, actual, delta

# Refutations
refute_equal unexpected, actual
refute_nil value
refute_includes collection, item

# Custom messages
assert value, "Expected value to be truthy but was #{value.inspect}"
```

### B. Debugging Tests

```ruby
# Add debugger
require 'debug'
def test_something
  debugger
  # Test code
end

# Print values
def test_something
  puts "Value: #{value.inspect}"
  pp complex_object
end

# Use flunk for debugging
def test_something
  flunk "Got here with value: #{value}"
end
```

### C. Performance Testing Tools

```ruby
require 'benchmark'

def test_publish_performance
  transport = create_test_transport
  message = TestMessage.new(data: 'test')

  time = Benchmark.measure do
    1000.times { transport.publish(message) }
  end

  puts "Published 1000 messages in #{time.real} seconds"
  assert time.real < 1.0, "Publishing too slow: #{time.real}s"
end
```

---

**Document Version:** 1.0
**Last Updated:** 2025-11-13
**Maintained By:** SmartMessage Development Team
