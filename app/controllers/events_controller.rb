class EventsController < InspectorController
  def show
    @event = Event.includes(deliveries: [ :destination, :delivery_attempts ]).find(params[:id])
  end
end
