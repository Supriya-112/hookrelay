class SourcesController < InspectorController
  # How many events a source page shows. Enough to see what just happened without
  # loading a busy source's whole history.
  RECENT_EVENTS = 50

  # success_rate and avg_latency_ms are nil when there's nothing to compute them
  # from yet — a destination with no concluded deliveries, or none that ever
  # succeeded.
  DestinationStats = Struct.new(:success_rate, :avg_latency_ms, :retries)

  def index
    @sources = account.sources.order(:name)
    # Counted in one query each rather than per row, so the dashboard doesn't get
    # slower as sources are added.
    @event_counts = account.events.group(:source_id).count
    @last_received = account.events.group(:source_id).maximum(:created_at)
  end

  def show
    @source = account.sources.find(params[:id])
    @destinations = @source.destinations.order(:created_at)
    @destination_stats = destination_stats(@destinations)
    @events = @source.events
                     .includes(deliveries: :destination)
                     .order(created_at: :desc)
                     .limit(RECENT_EVENTS)
  end

  private

  # Counted in a handful of grouped queries rather than per destination, same as
  # the counts on #index.
  def destination_stats(destinations)
    ids = destinations.map(&:id)
    return {} if ids.empty?

    # A delivery still pending, delivering, or waiting on a retry hasn't
    # succeeded or failed yet — counting it either way would misstate the rate.
    concluded = Delivery.where(destination_id: ids, status: %i[succeeded dead])
                         .group(:destination_id, :status).count

    attempts = DeliveryAttempt.joins(:delivery).where(deliveries: { destination_id: ids })
    total_attempts = attempts.group("deliveries.destination_id").count
    # Each delivery's first attempt is expected; only what comes after it is a
    # retry. Kept correct across replays, which leave earlier attempts in place
    # as history rather than resetting the count (see Delivery#reset_for_replay!).
    attempted_deliveries = attempts.group("deliveries.destination_id").distinct.count(:delivery_id)
    # A failed attempt's duration says nothing about how fast the destination
    # normally responds, and a connection error often has no duration at all.
    avg_latency = attempts.where(status_code: WebhookClient::SUCCESS_STATUSES)
                           .group("deliveries.destination_id").average(:duration_ms)

    ids.index_with do |id|
      succeeded = concluded[[ id, "succeeded" ]] || 0
      dead = concluded[[ id, "dead" ]] || 0
      finished = succeeded + dead

      DestinationStats.new(
        finished.zero? ? nil : succeeded.to_f / finished,
        avg_latency[id]&.round,
        (total_attempts[id] || 0) - (attempted_deliveries[id] || 0)
      )
    end
  end
end
