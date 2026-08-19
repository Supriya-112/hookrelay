# Re-delivers what has already been received: a whole event to every destination,
# or one destination's delivery on its own. Nothing is copied — the delivery keeps
# its identity and its attempt history, and starts a new run with a fresh retry
# budget.
class ReplaysController < InspectorController
  # A JSON caller is a script holding an API credential, not a browser carrying a
  # session cookie, so there is nothing for a forged cross-site request to ride
  # on. The inspector's own buttons post HTML and keep the check.
  skip_forgery_protection if: -> { request.format.json? }

  def event
    event = Event.find(params[:id])
    replayed = event.replay
    destinations = event.source.destinations.count

    respond_to do |format|
      format.html { redirect_to event_path(event), notice: event_notice(destinations) }
      format.json do
        render json: { event_id: event.id, destinations: destinations, deliveries_reset: replayed.size },
               status: :accepted
      end
    end
  end

  def delivery
    delivery = Delivery.find(params[:id])
    queued = delivery.replay

    respond_to do |format|
      format.html { redirect_to event_path(delivery.event), notice: delivery_notice(delivery, queued) }
      format.json do
        render json: { delivery_id: delivery.id, status: delivery.reload.status },
               status: queued ? :accepted : :conflict
      end
    end
  end

  private

  def event_notice(destinations)
    return "This source has no destinations to deliver to." if destinations.zero?

    "Replaying to #{helpers.pluralize(destinations, "destination")}."
  end

  def delivery_notice(delivery, queued)
    return "Replaying to #{delivery.destination.url}." if queued

    "That delivery is already on its way."
  end
end
