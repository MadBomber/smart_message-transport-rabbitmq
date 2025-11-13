# frozen_string_literal: true

module SmartMessage
  module Transport
    class RabbitMQ
      # Circuit Breaker implementation for transport operations
      # Prevents cascading failures by tracking errors and opening circuits
      class CircuitBreaker
        STATES = [:closed, :open, :half_open].freeze

        attr_reader :name, :state, :failure_count, :last_failure_time, :config

        def initialize(name, config = {})
          @name = name
          @config = default_config.merge(config)
          @state = :closed
          @failure_count = 0
          @last_failure_time = nil
          @success_count = 0
          @mutex = Mutex.new
        end

        def call(&block)
          check_state

          if @state == :open
            raise CircuitOpenError, "Circuit #{@name} is open"
          end

          begin
            result = block.call
            on_success
            result
          rescue => error
            on_failure(error)
            raise
          end
        end

        def on_success
          @mutex.synchronize do
            @failure_count = 0
            @success_count += 1

            # Half-open -> closed after successful calls
            if @state == :half_open && @success_count >= @config[:success_threshold]
              transition_to(:closed)
              @success_count = 0
            end
          end
        end

        def on_failure(error)
          @mutex.synchronize do
            @failure_count += 1
            @last_failure_time = Time.now

            if should_open?
              transition_to(:open)
              execute_fallback(error) if @config[:fallback]
            end
          end
        end

        def reset!
          @mutex.synchronize do
            @failure_count = 0
            @success_count = 0
            @last_failure_time = nil
            transition_to(:closed)
          end
        end

        def stats
          {
            name: @name,
            state: @state,
            failure_count: @failure_count,
            last_failure_time: @last_failure_time,
            success_count: @success_count
          }
        end

        private

        def default_config
          {
            failure_threshold: 5,
            timeout: 60,
            reset_timeout: 30,
            success_threshold: 2,
            fallback: nil
          }
        end

        def check_state
          return unless @state == :open

          @mutex.synchronize do
            if time_since_open > @config[:reset_timeout]
              transition_to(:half_open)
              @success_count = 0
            end
          end
        end

        def should_open?
          return false unless @state == :closed

          # Check if failures exceed threshold within timeout window
          if @failure_count >= @config[:failure_threshold]
            if @last_failure_time && (Time.now - @last_failure_time) < @config[:timeout]
              return true
            end
          end

          false
        end

        def time_since_open
          @last_failure_time ? Time.now - @last_failure_time : Float::INFINITY
        end

        def transition_to(new_state)
          return if @state == new_state

          old_state = @state
          @state = new_state
          logger.info { "[CircuitBreaker] #{@name}: #{old_state} -> #{new_state}" }
        end

        def execute_fallback(error)
          @config[:fallback].call(error) if @config[:fallback].respond_to?(:call)
        rescue => e
          logger.error { "[CircuitBreaker] Fallback failed for #{@name}: #{e.message}" }
        end

        def logger
          @logger ||= SmartMessage::Logger.default
        end

        class CircuitOpenError < StandardError; end
      end
    end
  end
end
