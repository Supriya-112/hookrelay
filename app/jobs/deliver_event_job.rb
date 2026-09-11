# Fans a received event out to each of its source's destinations, creating one
# Delivery per destination and queuing that delivery's first attempt. Splitting
# fan-out from the attempt keeps each destination's delivery independent (which
# retries rely on) and keeps the ingest request fast.
class DeliverEventJob < ApplicationJob
  queue_as :default

  def perform(event)
    jobs = event.source.destinations.map { |destination| DeliveryJob.new(delivery_for(event, destination)) }
    ActiveJob.perform_all_later(jobs)
  end

  private

  # Two runs of this job for the same event can reach a destination together; the
  # unique index on (event, destination) settles it and the loser carries on with
  # the row that won.
  def delivery_for(event, destination)
    Delivery.find_or_create_by!(event: event, destination: destination)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    Delivery.find_by!(event: event, destination: destination)
  end
end
