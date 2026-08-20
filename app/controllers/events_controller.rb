class EventsController < InspectorController
  def show
    @event = account.events.includes(deliveries: [ :destination, :delivery_attempts ]).find(params[:id])
  end
end
