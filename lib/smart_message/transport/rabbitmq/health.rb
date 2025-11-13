# frozen_string_literal: true

require 'time'

module SmartMessage
  module Transport
    class RabbitMQ
      # Health check implementation for RabbitMQ transport
      # Monitors connection, consumers, circuits, and queues
      class Health
        HEALTHY = :healthy
        DEGRADED = :degraded
        UNHEALTHY = :unhealthy

        attr_reader :transport

        def initialize(transport)
          @transport = transport
        end

        # Get overall health status
        def health_status
          components = {
            connection: connection_health,
            consumers: consumer_health,
            circuits: circuit_health,
            queues: queue_health,
            dlq: dlq_health
          }

          overall_status = determine_overall_status(components)

          {
            status: overall_status,
            timestamp: Time.now.iso8601,
            components: components,
            summary: build_summary(components)
          }
        end

        # Quick health check (just connection)
        def alive?
          connection_health[:status] == HEALTHY
        end

        # Detailed health check
        def ready?
          status = health_status
          status[:status] == HEALTHY
        end

        private

        # Check connection health
        def connection_health
          return { status: UNHEALTHY, message: 'Not connected' } unless @transport.connected?

          begin
            # Check if connection is actually usable
            return { status: UNHEALTHY, message: 'Channel closed' } if @transport.channel&.closed?

            { status: HEALTHY, message: 'Connection active' }
          rescue => e
            { status: UNHEALTHY, message: "Connection error: #{e.message}" }
          end
        end

        # Check consumer health
        def consumer_health
          consumers = @transport.consumers || {}
          active_count = consumers.count { |_, consumer| consumer && !consumer.cancelled? }

          if active_count == 0
            { status: DEGRADED, message: 'No active consumers', count: 0 }
          else
            { status: HEALTHY, message: "#{active_count} active consumers", count: active_count }
          end
        rescue => e
          { status: UNHEALTHY, message: "Consumer check failed: #{e.message}", count: 0 }
        end

        # Check circuit breaker health
        def circuit_health
          circuits = @transport.circuits || {}

          open_circuits = circuits.select { |_, circuit| circuit.state == :open }
          half_open_circuits = circuits.select { |_, circuit| circuit.state == :half_open }

          if open_circuits.any?
            {
              status: UNHEALTHY,
              message: "#{open_circuits.size} circuits open",
              open: open_circuits.keys,
              half_open: half_open_circuits.keys
            }
          elsif half_open_circuits.any?
            {
              status: DEGRADED,
              message: "#{half_open_circuits.size} circuits recovering",
              open: [],
              half_open: half_open_circuits.keys
            }
          else
            {
              status: HEALTHY,
              message: 'All circuits closed',
              open: [],
              half_open: []
            }
          end
        rescue => e
          { status: UNHEALTHY, message: "Circuit check failed: #{e.message}" }
        end

        # Check queue health
        def queue_health
          queues = @transport.queues || {}

          return { status: DEGRADED, message: 'No queues configured', count: 0 } if queues.empty?

          queue_stats = queues.map do |name, queue|
            begin
              {
                name: name,
                message_count: queue.message_count,
                consumer_count: queue.consumer_count,
                healthy: true
              }
            rescue => e
              {
                name: name,
                error: e.message,
                healthy: false
              }
            end
          end

          unhealthy_queues = queue_stats.select { |q| !q[:healthy] }
          overloaded_queues = queue_stats.select { |q| q[:healthy] && q[:message_count] && q[:message_count] > 10000 }

          if unhealthy_queues.any?
            {
              status: UNHEALTHY,
              message: "#{unhealthy_queues.size} queues unhealthy",
              count: queues.size,
              queues: queue_stats
            }
          elsif overloaded_queues.any?
            {
              status: DEGRADED,
              message: "#{overloaded_queues.size} queues overloaded",
              count: queues.size,
              queues: queue_stats
            }
          else
            {
              status: HEALTHY,
              message: "#{queues.size} queues healthy",
              count: queues.size,
              queues: queue_stats
            }
          end
        rescue => e
          { status: UNHEALTHY, message: "Queue check failed: #{e.message}" }
        end

        # Check DLQ health
        def dlq_health
          dlq = @transport.dlq

          return { status: HEALTHY, message: 'DLQ disabled' } unless dlq

          begin
            stats = dlq.stats
            message_count = stats[:message_count] || 0

            if message_count > 1000
              {
                status: DEGRADED,
                message: "DLQ has #{message_count} messages",
                message_count: message_count
              }
            elsif message_count > 100
              {
                status: DEGRADED,
                message: "DLQ has #{message_count} messages",
                message_count: message_count
              }
            else
              {
                status: HEALTHY,
                message: "DLQ has #{message_count} messages",
                message_count: message_count
              }
            end
          rescue => e
            { status: UNHEALTHY, message: "DLQ check failed: #{e.message}" }
          end
        end

        # Determine overall status from component statuses
        def determine_overall_status(components)
          statuses = components.values.map { |c| c[:status] }

          if statuses.include?(UNHEALTHY)
            UNHEALTHY
          elsif statuses.include?(DEGRADED)
            DEGRADED
          else
            HEALTHY
          end
        end

        # Build human-readable summary
        def build_summary(components)
          unhealthy = components.select { |_, c| c[:status] == UNHEALTHY }
          degraded = components.select { |_, c| c[:status] == DEGRADED }

          if unhealthy.any?
            messages = unhealthy.map { |name, c| "#{name}: #{c[:message]}" }
            "Unhealthy - #{messages.join('; ')}"
          elsif degraded.any?
            messages = degraded.map { |name, c| "#{name}: #{c[:message]}" }
            "Degraded - #{messages.join('; ')}"
          else
            "All systems healthy"
          end
        end
      end
    end
  end
end
