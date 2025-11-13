# frozen_string_literal: true

module SmartMessage
  module Transport
    class RabbitMQ
      # Dead Letter Queue handler for failed messages
      # Stores messages that fail processing for later analysis or retry
      class DeadLetterQueue
        attr_reader :channel, :dlq_exchange_name, :dlq_queue_name

        def initialize(channel, exchange_name, options = {})
          @channel = channel
          @dlq_exchange_name = "#{exchange_name}.dlq"
          @dlq_queue_name = "#{exchange_name}.dlq.queue"
          @options = default_options.merge(options)
          @mutex = Mutex.new

          setup_dlq
        end

        # Send a failed message to the DLQ
        def send_to_dlq(message_class, payload, routing_key, error, metadata = {})
          @mutex.synchronize do
            dlq_message = build_dlq_message(message_class, payload, routing_key, error, metadata)

            @dlq_exchange.publish(
              dlq_message.to_json,
              routing_key: "dlq.#{routing_key}",
              persistent: true,
              timestamp: Time.now.to_i,
              content_type: 'application/json',
              headers: {
                'x-death-reason' => error.class.name,
                'x-death-message' => truncate_error(error.message),
                'x-original-routing-key' => routing_key,
                'x-original-message-class' => message_class.to_s,
                'x-death-timestamp' => Time.now.to_i
              }
            )

            logger.info { "[DLQ] Sent message to DLQ: #{message_class} (#{routing_key})" }
            logger.debug { "[DLQ] Error: #{error.message}" }
          end
        rescue => e
          logger.error { "[DLQ] Failed to send to DLQ: #{e.message}" }
          # Don't raise - DLQ failure shouldn't stop the system
        end

        # Get messages from DLQ for inspection
        def inspect_messages(limit: 10)
          messages = []

          limit.times do
            delivery_info, properties, payload = @dlq_queue.pop(manual_ack: false)
            break unless delivery_info

            messages << {
              routing_key: delivery_info.routing_key,
              headers: properties.headers,
              payload: JSON.parse(payload),
              delivery_tag: delivery_info.delivery_tag
            }
          end

          messages
        rescue => e
          logger.error { "[DLQ] Failed to inspect messages: #{e.message}" }
          []
        end

        # Retry a message from DLQ by republishing to original exchange
        def retry_message(delivery_tag, original_exchange)
          delivery_info, properties, payload = @dlq_queue.get(delivery_tag, manual_ack: true)
          return false unless delivery_info

          dlq_data = JSON.parse(payload)
          original_routing_key = properties.headers['x-original-routing-key']

          # Republish to original exchange
          original_exchange.publish(
            dlq_data['original_payload'],
            routing_key: original_routing_key,
            persistent: true
          )

          # Acknowledge the DLQ message
          @channel.ack(delivery_info.delivery_tag)

          logger.info { "[DLQ] Retried message from DLQ: #{original_routing_key}" }
          true
        rescue => e
          logger.error { "[DLQ] Failed to retry message: #{e.message}" }
          false
        end

        # Get DLQ statistics
        def stats
          {
            queue_name: @dlq_queue_name,
            message_count: message_count,
            consumer_count: consumer_count
          }
        rescue => e
          logger.error { "[DLQ] Failed to get stats: #{e.message}" }
          { queue_name: @dlq_queue_name, message_count: 0, consumer_count: 0 }
        end

        # Purge all messages from DLQ
        def purge!
          @mutex.synchronize do
            @dlq_queue.purge
            logger.info { "[DLQ] Purged DLQ: #{@dlq_queue_name}" }
          end
        rescue => e
          logger.error { "[DLQ] Failed to purge: #{e.message}" }
        end

        private

        def default_options
          {
            durable: true,
            auto_delete: false,
            ttl: 7 * 24 * 60 * 60 * 1000 # 7 days in milliseconds
          }
        end

        def setup_dlq
          # Create DLQ exchange
          @dlq_exchange = @channel.exchange(
            @dlq_exchange_name,
            type: :topic,
            durable: @options[:durable],
            auto_delete: @options[:auto_delete]
          )

          # Create DLQ queue with TTL
          queue_args = {}
          queue_args['x-message-ttl'] = @options[:ttl] if @options[:ttl]

          @dlq_queue = @channel.queue(
            @dlq_queue_name,
            durable: @options[:durable],
            auto_delete: @options[:auto_delete],
            arguments: queue_args
          )

          # Bind DLQ queue to DLQ exchange
          @dlq_queue.bind(@dlq_exchange, routing_key: 'dlq.#')

          logger.debug { "[DLQ] Setup complete: #{@dlq_exchange_name}" }
        end

        def build_dlq_message(message_class, payload, routing_key, error, metadata)
          {
            message_class: message_class.to_s,
            original_payload: payload,
            routing_key: routing_key,
            error: {
              class: error.class.name,
              message: error.message,
              backtrace: error.backtrace&.first(5)
            },
            metadata: metadata,
            timestamp: Time.now.iso8601,
            retry_count: metadata[:retry_count] || 0
          }
        end

        def truncate_error(message, max_length: 500)
          return message if message.length <= max_length
          "#{message[0...max_length]}... (truncated)"
        end

        def message_count
          @dlq_queue.message_count
        rescue => e
          logger.error { "[DLQ] Failed to get message count: #{e.message}" }
          0
        end

        def consumer_count
          @dlq_queue.consumer_count
        rescue => e
          0
        end

        def logger
          @logger ||= SmartMessage::Logger.default
        end
      end
    end
  end
end
