# frozen_string_literal: true

require "test_helper"

class TestCircuitBreaker < Minitest::Test
  def setup
    @circuit = SmartMessage::Transport::RabbitMQ::CircuitBreaker.new(:test)
  end

  def test_initialization
    assert_equal :test, @circuit.name
    assert_equal :closed, @circuit.state
    assert_equal 0, @circuit.failure_count
  end

  def test_call_executes_block_when_closed
    result = @circuit.call { "success" }
    assert_equal "success", result
  end

  def test_on_success_resets_failure_count
    @circuit.instance_variable_set(:@failure_count, 3)
    @circuit.on_success

    assert_equal 0, @circuit.failure_count
  end

  def test_on_failure_increments_count
    @circuit.on_failure(StandardError.new("test"))
    assert_equal 1, @circuit.failure_count
    refute_nil @circuit.last_failure_time
  end

  def test_circuit_opens_after_threshold_failures
    5.times { @circuit.on_failure(StandardError.new("test")) }

    assert_equal :open, @circuit.state
  end

  def test_call_raises_when_circuit_open
    # Force circuit to open
    5.times { @circuit.on_failure(StandardError.new("test")) }

    error = assert_raises(SmartMessage::Transport::RabbitMQ::CircuitBreaker::CircuitOpenError) do
      @circuit.call { "should not execute" }
    end

    assert_match /Circuit test is open/, error.message
  end

  def test_circuit_transitions_to_half_open_after_reset_timeout
    # Open the circuit
    5.times { @circuit.on_failure(StandardError.new("test")) }
    assert_equal :open, @circuit.state

    # Simulate time passage
    @circuit.instance_variable_set(:@last_failure_time, Time.now - 31)

    # Should transition to half_open on next check
    @circuit.send(:check_state)
    assert_equal :half_open, @circuit.state
  end

  def test_half_open_closes_after_successful_calls
    # Get to half_open state
    5.times { @circuit.on_failure(StandardError.new("test")) }
    @circuit.instance_variable_set(:@last_failure_time, Time.now - 31)
    @circuit.send(:check_state)
    assert_equal :half_open, @circuit.state

    # Successful calls should close it
    2.times { @circuit.on_success }
    assert_equal :closed, @circuit.state
  end

  def test_reset_clears_state
    # Build up some state
    3.times { @circuit.on_failure(StandardError.new("test")) }

    @circuit.reset!

    assert_equal :closed, @circuit.state
    assert_equal 0, @circuit.failure_count
    assert_nil @circuit.last_failure_time
  end

  def test_stats_returns_circuit_information
    @circuit.on_failure(StandardError.new("test"))

    stats = @circuit.stats

    assert_equal :test, stats[:name]
    assert_equal :closed, stats[:state]
    assert_equal 1, stats[:failure_count]
    refute_nil stats[:last_failure_time]
  end

  def test_call_with_failure_records_error
    begin
      @circuit.call { raise StandardError, "test error" }
    rescue StandardError
      # Expected
    end

    assert_equal 1, @circuit.failure_count
  end

  def test_fallback_executed_when_circuit_opens
    fallback_called = false
    fallback = proc { |error| fallback_called = true }

    circuit = SmartMessage::Transport::RabbitMQ::CircuitBreaker.new(
      :test,
      failure_threshold: 2,
      fallback: fallback
    )

    # Trigger failures to open circuit
    2.times { circuit.on_failure(StandardError.new("test")) }

    assert fallback_called, "Fallback should have been called"
  end

  def test_custom_configuration
    circuit = SmartMessage::Transport::RabbitMQ::CircuitBreaker.new(
      :custom,
      failure_threshold: 10,
      timeout: 120,
      reset_timeout: 60
    )

    assert_equal 10, circuit.config[:failure_threshold]
    assert_equal 120, circuit.config[:timeout]
    assert_equal 60, circuit.config[:reset_timeout]
  end
end
