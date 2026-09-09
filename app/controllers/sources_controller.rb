class SourcesController < InspectorController
  # How many events a source page shows. Enough to see what just happened without
  # loading a busy source's whole history.
  RECENT_EVENTS = 50

  # success_rate and avg_latency_ms are nil when there's nothing to compute them
  # from yet — a destination with no concluded deliveries, or none that ever
  # succeeded.
  DestinationStats = Struct.new(:success_rate, :avg_latency_ms, :retries, keyword_init: true)

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
    concluded = Delivery.where(destination_id: ids, status: Delivery::CONCLUDED_STATUSES)
                         .group(:destination_id, :status).count
    concluded.default = 0

    # Total and distinct-delivery counts come from one query, not two, so a
    # delivery written between them can't leave retries negative — one attempt
    # counted toward the total but its delivery not yet counted as attempted.
    # This also counts attempts from deliveries still retrying, not just ones
    # that have concluded: it's meant to reflect retry activity as it happens,
    # unlike success rate and latency below.
    attempt_counts = DeliveryAttempt.joins(:delivery)
                                     .where(deliveries: { destination_id: ids })
                                     .group("deliveries.destination_id")
                                     .pluck(Arel.sql("deliveries.destination_id"), Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT delivery_attempts.delivery_id)"))
                                     .to_h { |id, total, attempted| [ id, [ total, attempted ] ] }
    attempt_counts.default = [ 0, 0 ]

    # A failed attempt's duration doesn't reflect how fast the destination
    # normally responds, so only a successful attempt's timing counts here.
    avg_latency = DeliveryAttempt.successful.joins(:delivery)
                                  .where(deliveries: { destination_id: ids })
                                  .group("deliveries.destination_id").average(:duration_ms)

    ids.index_with do |id|
      succeeded = concluded[[ id, "succeeded" ]]
      dead = concluded[[ id, "dead" ]]
      finished = succeeded + dead
      total, attempted = attempt_counts[id]

      DestinationStats.new(
        success_rate: finished.zero? ? nil : succeeded.to_f / finished,
        avg_latency_ms: avg_latency[id]&.round,
        # Each delivery's first attempt is expected; only what comes after it
        # is a retry. A replay starts a fresh cycle, and that cycle's own first
        # attempt is counted the same way here — so a delivery replayed and
        # redelivered without needing a retry this time still adds one. Not
        # worth tracking replay cycles just to avoid that.
        retries: total - attempted
      )
    end
  end
end
