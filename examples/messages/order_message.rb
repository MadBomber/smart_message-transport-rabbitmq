# frozen_string_literal: true

require 'smart_message'

class OrderMessage < SmartMessage::Base
  property :order_id, required: true
  property :customer_id, required: true
  property :amount, required: true

  def process
    puts "Processing order #{order_id} for customer #{customer_id}: $#{amount}"
  end
end