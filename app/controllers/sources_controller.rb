class SourcesController < InspectorController
  # How many events a source page shows. Enough to see what just happened without
  # loading a busy source's whole history.
  RECENT_EVENTS = 50

  def index
    @sources = Source.order(:name)
    # Counted in one query each rather than per row, so the dashboard doesn't get
    # slower as sources are added.
    @event_counts = Event.group(:source_id).count
    @last_received = Event.group(:source_id).maximum(:created_at)
  end

  def show
    @source = Source.find(params[:id])
    @destinations = @source.destinations.order(:created_at)
    @events = @source.events
                     .includes(deliveries: :destination)
                     .order(created_at: :desc)
                     .limit(RECENT_EVENTS)
  end
end
