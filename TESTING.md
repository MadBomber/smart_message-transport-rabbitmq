# Testing Guide
## SmartMessage::Transport::RabbitMQ

This guide provides practical instructions for running and writing tests for the RabbitMQ transport adapter.

---

## Quick Start

### Running All Tests

```bash
# Run the complete test suite
bundle exec rake test

# Run with verbose output
bundle exec rake test TESTOPTS="--verbose"
```

### Running Specific Test Types

```bash
# Unit tests only (fast, no external dependencies)
bundle exec rake test TEST="test/unit/**/*_test.rb"

# Integration tests
bundle exec rake test TEST="test/integration/**/*_test.rb"

# Single test file
bundle exec ruby test/unit/transport/test_rabbitmq.rb

# Single test method
bundle exec ruby test/unit/transport/test_rabbitmq.rb -n test_initialization
```

---

## Test Organization

### Current Test Structure

```
test/
├── test_helper.rb                              # Test configuration and mocks
├── support/
│   ├── mock_rabbitmq.rb                       # Mock RabbitMQ components
│   ├── test_helpers.rb                        # Helper methods
│   └── test_messages.rb                       # Test message classes
├── unit/
│   └── transport/
│       ├── test_rabbitmq.rb                   # Core transport tests
│       ├── test_rabbitmq_dispatcher.rb        # Dispatcher tests
│       ├── test_subscription_api.rb           # Subscription API tests
│       ├── test_connection_management.rb      # Connection tests
│       ├── test_publishing.rb                 # Publishing tests
│       └── test_routing_keys.rb               # Routing key tests
└── integration/
    ├── test_publish_subscribe.rb              # Pub/sub integration
    └── test_pattern_routing.rb                # Pattern routing tests
```

---

## Writing Tests

### Basic Test Template

```ruby
# frozen_string_literal: true

require "test_helper"

class TestYourFeature < Minitest::Test
  def setup
    @transport = create_test_transport
  end

  def teardown
    @transport&.disconnect
  end

  def test_your_feature_behavior
    # Arrange
    expected_value = "something"

    # Act
    actual_value = @transport.some_method

    # Assert
    assert_equal expected_value, actual_value
  end
end
```

### Using Test Helpers

The test suite provides several helper methods:

```ruby
# Create a test transport with mocked RabbitMQ
transport = create_test_transport

# Execute code with a transport
with_test_transport do |transport|
  # Your test code
end

# Assert message was published
assert_published(transport, "OrderMessage.service.api")

# Get published messages
messages = get_published_messages(transport)

# Create test messages
order = TestMessages.create(:order, order_id: "123", amount: 99.99)
```

### Testing with Mock RabbitMQ

All tests use mock RabbitMQ components by default:

```ruby
def test_publish_to_exchange
  transport = create_test_transport

  # Publish message
  transport.send(:do_publish, 'TestMessage', '{"data":"test"}', "TestMessage.broadcast.anonymous")

  # Verify in mock exchange
  exchange = transport.instance_variable_get(:@exchange)
  assert_equal 1, exchange.published_messages.length
end
```

---

## Test Coverage

### Current Coverage Status

| Component | Coverage | Status |
|-----------|----------|--------|
| Core Transport | ~70% | ✅ Good |
| Dispatcher | ~80% | ✅ Good |
| Connection Management | ~60% | ⚠️ Needs improvement |
| Publishing | ~75% | ✅ Good |
| Subscription API | ~70% | ✅ Good |
| Routing Keys | ~85% | ✅ Good |
| **Overall** | **~72%** | ⚠️ **Target: 90%** |

### Coverage Goals

See [TEST_PLAN.md](TEST_PLAN.md) for detailed coverage goals and strategies.

---

## Common Testing Patterns

### Testing Error Conditions

```ruby
def test_publish_raises_error_when_not_connected
  transport = create_test_transport
  transport.instance_variable_set(:@connection, nil)

  assert_raises(SmartMessage::Transport::RabbitMQ::Error) do
    transport.send(:do_publish, 'TestMessage', '{}', 'TestMessage.broadcast.anonymous')
  end
end
```

### Testing Async Behavior

```ruby
def test_async_message_processing
  transport = create_test_transport
  received = []

  transport.subscribe(TestMessages::OrderMessage) do |msg|
    received << msg
  end

  # Simulate async message delivery
  Thread.new do
    # Publish message
  end

  # Wait for processing
  wait_for(timeout: 1) { received.any? }

  assert_equal 1, received.length
end
```

### Testing Configuration

```ruby
def test_configuration_from_environment
  original_env = ENV.to_h

  begin
    ENV['RABBITMQ_HOST'] = 'test-host'
    ENV['RABBITMQ_PORT'] = '5673'

    transport = SmartMessage::Transport::RabbitMQ.new(
      serializer: MockSerializer.new
    )

    options = transport.instance_variable_get(:@options)
    assert_equal 'test-host', options[:host]
    assert_equal 5673, options[:port]
  ensure
    ENV.replace(original_env)
  end
end
```

---

## Debugging Tests

### Using the Debugger

```ruby
require 'debug'

def test_something
  transport = create_test_transport

  debugger  # Execution will pause here

  transport.some_method
end
```

### Printing Debug Information

```ruby
def test_with_debug_output
  transport = create_test_transport

  # Print variable values
  puts "Transport: #{transport.inspect}"

  # Pretty print complex objects
  require 'pp'
  pp transport.instance_variable_get(:@options)
end
```

### Using Flunk for Debugging

```ruby
def test_debugging
  transport = create_test_transport
  result = transport.some_method

  flunk "Result was: #{result.inspect}"  # Will fail and show result
end
```

---

## Continuous Integration

### Running Tests in CI

Tests are automatically run on pull requests and commits via GitHub Actions.

#### CI Configuration

See `.github/workflows/test.yml` for the complete CI setup.

### Pre-commit Hooks

Set up pre-commit hooks to run tests before committing:

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running tests before commit..."

bundle exec rake test:unit

if [ $? -ne 0 ]; then
  echo "Tests failed. Commit aborted."
  exit 1
fi

echo "Tests passed!"
exit 0
```

Make it executable:

```bash
chmod +x .git/hooks/pre-commit
```

---

## Troubleshooting

### Tests Failing Locally

1. **Update dependencies:**
   ```bash
   bundle install
   ```

2. **Clear test artifacts:**
   ```bash
   rm -rf coverage/
   ```

3. **Run with verbose output:**
   ```bash
   bundle exec rake test TESTOPTS="--verbose"
   ```

### Flaky Tests

If tests intermittently fail:

1. **Run with specific seed:**
   ```bash
   bundle exec rake test TESTOPTS="--seed=12345"
   ```

2. **Increase timeouts:**
   ```ruby
   wait_for(timeout: 5) { condition }  # Increase from default 1 second
   ```

3. **Add debugging output:**
   ```ruby
   puts "Current state: #{variable.inspect}"
   ```

### Mock Issues

If mocks behave unexpectedly:

1. **Verify mock setup:**
   ```ruby
   transport = create_test_transport
   assert transport.connected?, "Transport should be connected after setup"
   ```

2. **Check mock expectations:**
   ```ruby
   exchange = transport.instance_variable_get(:@exchange)
   assert_instance_of MockRabbitMQ::MockExchange, exchange
   ```

---

## Contributing Tests

### Before Submitting Tests

1. **Run the full test suite:**
   ```bash
   bundle exec rake test
   ```

2. **Run Rubocop:**
   ```bash
   bundle exec rubocop test/
   ```

3. **Verify test names are descriptive:**
   ```ruby
   # Good
   def test_publish_includes_routing_key_in_headers
   def test_subscribe_with_array_of_message_classes

   # Bad
   def test_publish
   def test_subscribe
   ```

4. **Ensure tests are independent:**
   - Each test should set up its own data
   - Tests should not depend on execution order
   - Use `setup` and `teardown` methods

### Test Guidelines

1. **One assertion per test** (when possible)
2. **Clear Arrange-Act-Assert structure**
3. **Descriptive test names**
4. **Include edge cases**
5. **Test error conditions**
6. **Add comments for complex setups**

---

## Resources

- [Minitest Documentation](https://github.com/seattlerb/minitest)
- [Test Plan](TEST_PLAN.md) - Comprehensive test strategy
- [Implementation Plan](IMPLEMENTATION_PLAN.md) - Development roadmap
- [RabbitMQ Testing Best Practices](https://www.rabbitmq.com/testing.html)

---

## Getting Help

If you're stuck on testing:

1. Check existing tests for similar patterns
2. Review [TEST_PLAN.md](TEST_PLAN.md) for guidelines
3. Look at test helpers in `test/support/`
4. Open an issue with your question

---

**Last Updated:** 2025-11-13
