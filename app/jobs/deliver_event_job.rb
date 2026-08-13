# Fans a received event out to each of its source's destinations, creating one
# Delivery per destination and queuing that delivery's first attempt. Splitting
# fan-out from the attempt keeps each destination's delivery independent (which
# retries in M3 rely on) and keeps the ingest request fast.
class DeliverEventJob < ApplicationJob
  queue_as :default

  def perform(event)
    event.source.destinations.find_each do |destination|
      delivery = Delivery.find_or_create_by!(event: event, destination: destination)
      DeliveryJob.perform_later(delivery)
    end
  end
end
