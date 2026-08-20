# Re-delivers what has already been received: a whole event to every destination,
# or one destination's delivery on its own. Nothing is copied — the delivery keeps
# its identity and its attempt history, and starts a new run with a fresh retry
# budget.
class ReplaysController < InspectorController
  # The only endpoints a script uses, so they take an API key as well as a
  # session; authenticate_either does both rather than the concern's session-only
  # check.
  allow_unauthenticated_access
  before_action :authenticate_either

  # A JSON caller holds a key rather than a session cookie, so there is nothing
  # for a forged cross-site request to ride on. The inspector's own buttons post
  # HTML and keep the check.
  skip_forgery_protection if: -> { request.format.json? }

  def event
    event = account.events.find(params[:id])
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
    delivery = account.deliveries.find(params[:id])
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

  def authenticate_either
    return if authenticated?
    return if authenticate_api_key

    respond_to do |format|
      format.html { request_authentication }
      format.json { head :unauthorized }
    end
  end

  # Authorization: Bearer hr_… — the key is looked up by digest, and its last use
  # is recorded so an unused or forgotten key can be spotted and revoked.
  def authenticate_api_key
    token, _options = ActionController::HttpAuthentication::Token.token_and_options(request)
    key = ApiKey.authenticate(token)
    return false unless key

    key.touch(:last_used_at)
    Current.api_key = key
    true
  end

  def event_notice(destinations)
    return "This source has no destinations to deliver to." if destinations.zero?

    "Replaying to #{helpers.pluralize(destinations, "destination")}."
  end

  def delivery_notice(delivery, queued)
    return "Replaying to #{delivery.destination.url}." if queued

    "That delivery is already on its way."
  end
end
