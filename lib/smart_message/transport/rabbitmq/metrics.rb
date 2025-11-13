# frozen_string_literal: true

module SmartMessage
  module Transport
    class RabbitMQ
      # Metrics collection for RabbitMQ transport
      # Tracks publishing, receiving, latency, errors, and circuit breaker state
      class Metrics
        attr_reader :data

        def initialize
          @data = {
            # Counters
            messages_published: 0,
            messages_received: 0,
            messages_failed: 0,
            connection_errors: 0,
            publish_errors: 0,
            subscribe_errors: 0,
            circuit_state_changes: 0,
            dlq_messages: 0,

            # Latency tracking (milliseconds)
            publish_latencies: [],
            processing_latencies: [],

            # Gauges (current values)
            active_consumers: 0,
            queue_depths: {},

            # Timestamps
            started_at: Time.now,
            last_published_at: nil,
            last_received_at: nil,
            last_error_at: nil
          }
          @mutex = Mutex.new
        end

        # Record a published message
        def record_publish(latency_ms = nil)
          @mutex.synchronize do
            @data[:messages_published] += 1
            @data[:last_published_at] = Time.now
            @data[:publish_latencies] << latency_ms if latency_ms
            trim_latencies(:publish_latencies)
          end
        end

        # Record a received message
        def record_receive(latency_ms = nil)
          @mutex.synchronize do
            @data[:messages_received] += 1
            @data[:last_received_at] = Time.now
            @data[:processing_latencies] << latency_ms if latency_ms
            trim_latencies(:processing_latencies)
          end
        end

        # Record a failed message
        def record_failure(error_type = :general)
          @mutex.synchronize do
            @data[:messages_failed] += 1
            @data[:last_error_at] = Time.now

            case error_type
            when :connection
              @data[:connection_errors] += 1
            when :publish
              @data[:publish_errors] += 1
            when :subscribe
              @data[:subscribe_errors] += 1
            end
          end
        end

        # Record a circuit breaker state change
        def record_circuit_state_change
          @mutex.synchronize do
            @data[:circuit_state_changes] += 1
          end
        end

        # Record a message sent to DLQ
        def record_dlq_message
          @mutex.synchronize do
            @data[:dlq_messages] += 1
          end
        end

        # Update consumer count
        def set_active_consumers(count)
          @mutex.synchronize do
            @data[:active_consumers] = count
          end
        end

        # Update queue depth for a specific queue
        def set_queue_depth(queue_name, depth)
          @mutex.synchronize do
            @data[:queue_depths][queue_name] = depth
          end
        end

        # Get statistics summary
        def stats
          @mutex.synchronize do
            {
              # Counters
              messages_published: @data[:messages_published],
              messages_received: @data[:messages_received],
              messages_failed: @data[:messages_failed],
              connection_errors: @data[:connection_errors],
              publish_errors: @data[:publish_errors],
              subscribe_errors: @data[:subscribe_errors],
              circuit_state_changes: @data[:circuit_state_changes],
              dlq_messages: @data[:dlq_messages],

              # Latency statistics
              publish_latency: calculate_latency_stats(:publish_latencies),
              processing_latency: calculate_latency_stats(:processing_latencies),

              # Gauges
              active_consumers: @data[:active_consumers],
              total_queue_depth: @data[:queue_depths].values.sum,
              queue_depths: @data[:queue_depths].dup,

              # Rates (per second)
              publish_rate: calculate_rate(:messages_published),
              receive_rate: calculate_rate(:messages_received),

              # Uptime
              uptime_seconds: (Time.now - @data[:started_at]).to_i,
              started_at: @data[:started_at],
              last_published_at: @data[:last_published_at],
              last_received_at: @data[:last_received_at],
              last_error_at: @data[:last_error_at]
            }
          end
        end

        # Reset all metrics
        def reset!
          @mutex.synchronize do
            @data[:messages_published] = 0
            @data[:messages_received] = 0
            @data[:messages_failed] = 0
            @data[:connection_errors] = 0
            @data[:publish_errors] = 0
            @data[:subscribe_errors] = 0
            @data[:circuit_state_changes] = 0
            @data[:dlq_messages] = 0
            @data[:publish_latencies].clear
            @data[:processing_latencies].clear
            @data[:started_at] = Time.now
            @data[:last_published_at] = nil
            @data[:last_received_at] = nil
            @data[:last_error_at] = nil
          end
        end

        private

        # Keep only last N latency measurements (default 1000)
        def trim_latencies(key, max_size = 1000)
          if @data[key].size > max_size
            @data[key] = @data[key].last(max_size)
          end
        end

        # Calculate latency statistics
        def calculate_latency_stats(key)
          latencies = @data[key]
          return { count: 0 } if latencies.empty?

          sorted = latencies.sort
          count = sorted.size

          {
            count: count,
            min: sorted.first,
            max: sorted.last,
            avg: sorted.sum.to_f / count,
            median: calculate_median(sorted),
            p95: calculate_percentile(sorted, 95),
            p99: calculate_percentile(sorted, 99)
          }
        end

        def calculate_median(sorted_array)
          mid = sorted_array.size / 2
          if sorted_array.size.odd?
            sorted_array[mid]
          else
            (sorted_array[mid - 1] + sorted_array[mid]) / 2.0
          end
        end

        def calculate_percentile(sorted_array, percentile)
          return nil if sorted_array.empty?

          index = (percentile / 100.0 * (sorted_array.size - 1)).ceil
          sorted_array[index]
        end

        # Calculate rate per second since start
        def calculate_rate(counter_key)
          uptime = Time.now - @data[:started_at]
          return 0.0 if uptime <= 0

          (@data[counter_key].to_f / uptime).round(2)
        end
      end
    end
  end
end
