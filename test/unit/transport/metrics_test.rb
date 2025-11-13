# frozen_string_literal: true

require "test_helper"

class TestMetrics < Minitest::Test
  def setup
    @metrics = SmartMessage::Transport::RabbitMQ::Metrics.new
  end

  def test_initialization
    assert_equal 0, @metrics.data[:messages_published]
    assert_equal 0, @metrics.data[:messages_received]
    assert_equal 0, @metrics.data[:messages_failed]
    assert_instance_of Time, @metrics.data[:started_at]
  end

  def test_record_publish
    @metrics.record_publish(10.5)

    assert_equal 1, @metrics.data[:messages_published]
    assert_equal [10.5], @metrics.data[:publish_latencies]
    assert_instance_of Time, @metrics.data[:last_published_at]
  end

  def test_record_receive
    @metrics.record_receive(15.2)

    assert_equal 1, @metrics.data[:messages_received]
    assert_equal [15.2], @metrics.data[:processing_latencies]
    assert_instance_of Time, @metrics.data[:last_received_at]
  end

  def test_record_failure_general
    @metrics.record_failure

    assert_equal 1, @metrics.data[:messages_failed]
    assert_instance_of Time, @metrics.data[:last_error_at]
  end

  def test_record_failure_by_type
    @metrics.record_failure(:connection)
    @metrics.record_failure(:publish)
    @metrics.record_failure(:subscribe)

    assert_equal 3, @metrics.data[:messages_failed]
    assert_equal 1, @metrics.data[:connection_errors]
    assert_equal 1, @metrics.data[:publish_errors]
    assert_equal 1, @metrics.data[:subscribe_errors]
  end

  def test_record_circuit_state_change
    @metrics.record_circuit_state_change

    assert_equal 1, @metrics.data[:circuit_state_changes]
  end

  def test_record_dlq_message
    @metrics.record_dlq_message

    assert_equal 1, @metrics.data[:dlq_messages]
  end

  def test_set_active_consumers
    @metrics.set_active_consumers(5)

    assert_equal 5, @metrics.data[:active_consumers]
  end

  def test_set_queue_depth
    @metrics.set_queue_depth("test_queue", 100)
    @metrics.set_queue_depth("another_queue", 50)

    assert_equal 100, @metrics.data[:queue_depths]["test_queue"]
    assert_equal 50, @metrics.data[:queue_depths]["another_queue"]
  end

  def test_stats_returns_summary
    @metrics.record_publish(10.0)
    @metrics.record_publish(20.0)
    @metrics.record_receive(15.0)
    @metrics.record_failure(:connection)
    @metrics.set_active_consumers(3)

    stats = @metrics.stats

    assert_equal 2, stats[:messages_published]
    assert_equal 1, stats[:messages_received]
    assert_equal 1, stats[:messages_failed]
    assert_equal 1, stats[:connection_errors]
    assert_equal 3, stats[:active_consumers]
    assert_instance_of Hash, stats[:publish_latency]
    assert_instance_of Hash, stats[:processing_latency]
  end

  def test_latency_statistics
    # Add multiple latency measurements
    [10, 20, 30, 40, 50].each { |lat| @metrics.record_publish(lat) }

    stats = @metrics.stats[:publish_latency]

    assert_equal 5, stats[:count]
    assert_equal 10, stats[:min]
    assert_equal 50, stats[:max]
    assert_equal 30.0, stats[:avg]
    assert_equal 30, stats[:median]
  end

  def test_latency_percentiles
    # Add 100 measurements
    100.times { |i| @metrics.record_publish(i + 1) }

    stats = @metrics.stats[:publish_latency]

    assert stats[:p95] >= 95
    assert stats[:p99] >= 99
  end

  def test_rate_calculation
    @metrics.record_publish
    @metrics.record_publish
    @metrics.record_receive

    # Allow some time to pass
    sleep 0.1

    stats = @metrics.stats

    assert stats[:publish_rate] > 0
    assert stats[:receive_rate] > 0
  end

  def test_uptime_tracking
    stats = @metrics.stats

    assert stats[:uptime_seconds] >= 0
    assert_instance_of Time, stats[:started_at]
  end

  def test_reset_clears_metrics
    @metrics.record_publish(10.0)
    @metrics.record_receive(15.0)
    @metrics.record_failure
    @metrics.set_active_consumers(5)

    @metrics.reset!

    assert_equal 0, @metrics.data[:messages_published]
    assert_equal 0, @metrics.data[:messages_received]
    assert_equal 0, @metrics.data[:messages_failed]
    assert_equal 0, @metrics.data[:publish_latencies].size
    assert_nil @metrics.data[:last_published_at]
  end

  def test_trim_latencies_keeps_limit
    # Add more than 1000 latency measurements
    1500.times { |i| @metrics.record_publish(i) }

    # Should only keep last 1000
    assert_equal 1000, @metrics.data[:publish_latencies].size
  end

  def test_thread_safety
    threads = 10.times.map do
      Thread.new do
        100.times { @metrics.record_publish }
      end
    end

    threads.each(&:join)

    assert_equal 1000, @metrics.data[:messages_published]
  end

  def test_queue_depth_summary
    @metrics.set_queue_depth("queue1", 100)
    @metrics.set_queue_depth("queue2", 200)
    @metrics.set_queue_depth("queue3", 300)

    stats = @metrics.stats

    assert_equal 600, stats[:total_queue_depth]
    assert_equal 3, stats[:queue_depths].size
  end

  def test_empty_latency_stats
    stats = @metrics.stats

    assert_equal 0, stats[:publish_latency][:count]
    assert_equal 0, stats[:processing_latency][:count]
  end
end
