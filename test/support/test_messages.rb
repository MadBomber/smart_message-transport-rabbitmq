# frozen_string_literal: true

require 'securerandom'

# Test message classes for use in test suite

module TestMessages
  class TestMessage
    attr_accessor :data, :timestamp, :id

    def initialize(data: nil, timestamp: Time.now, id: nil)
      @data = data
      @timestamp = timestamp
      @id = id || SecureRandom.uuid
    end

    def self.to_s
      'TestMessage'
    end

    def class
      TestMessage
    end

    def _sm_header
      TestMessageHeader.new
    end
  end

  class OrderMessage
    attr_accessor :order_id, :customer_id, :amount, :items, :status

    def initialize(order_id: nil, customer_id: nil, amount: 0.0, items: [], status: 'pending')
      @order_id = order_id || "ORD-#{SecureRandom.hex(4)}"
      @customer_id = customer_id
      @amount = amount
      @items = items
      @status = status
    end

    def self.to_s
      'OrderMessage'
    end

    def self.name
      'OrderMessage'
    end

    def class
      OrderMessage
    end

    def _sm_header
      TestMessageHeader.new
    end
  end

  class PaymentMessage
    attr_accessor :payment_id, :order_id, :amount, :status, :method

    def initialize(payment_id: nil, order_id: nil, amount: 0.0, status: 'pending', method: 'credit_card')
      @payment_id = payment_id || "PAY-#{SecureRandom.hex(4)}"
      @order_id = order_id
      @amount = amount
      @status = status
      @method = method
    end

    def self.to_s
      'PaymentMessage'
    end

    def self.name
      'PaymentMessage'
    end

    def class
      PaymentMessage
    end

    def _sm_header
      TestMessageHeader.new
    end
  end

  class AlertMessage
    attr_accessor :severity, :message, :service, :timestamp

    def initialize(severity: 'info', message: '', service: 'unknown', timestamp: Time.now)
      @severity = severity
      @message = message
      @service = service
      @timestamp = timestamp
    end

    def self.to_s
      'AlertMessage'
    end

    def self.name
      'AlertMessage'
    end

    def class
      AlertMessage
    end

    def _sm_header
      TestMessageHeader.new
    end
  end

  class NotificationMessage
    attr_accessor :recipient, :subject, :body, :priority

    def initialize(recipient: nil, subject: '', body: '', priority: 'normal')
      @recipient = recipient
      @subject = subject
      @body = body
      @priority = priority
    end

    def self.to_s
      'NotificationMessage'
    end

    def self.name
      'NotificationMessage'
    end

    def class
      NotificationMessage
    end

    def _sm_header
      TestMessageHeader.new
    end
  end

  class TestMessageHeader
    attr_accessor :to, :from, :timestamp, :correlation_id

    def initialize
      @to = nil
      @from = nil
      @timestamp = Time.now
      @correlation_id = SecureRandom.uuid
    end
  end

  # Helper method to create test message instances
  def self.create(type, **attributes)
    case type
    when :test
      TestMessage.new(**attributes)
    when :order
      OrderMessage.new(**attributes)
    when :payment
      PaymentMessage.new(**attributes)
    when :alert
      AlertMessage.new(**attributes)
    when :notification
      NotificationMessage.new(**attributes)
    else
      raise ArgumentError, "Unknown message type: #{type}"
    end
  end
end
