Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  # First-run setup; closed once an account exists. See RegistrationsController.
  resource :registration, only: [ :new, :create ]
  resources :api_keys, only: [ :index, :create, :destroy ]
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Webhook ingest: providers POST events to a source's unique token URL.
  post "in/:token" => "ingest#create", as: :ingest

  # The inspector.
  root "sources#index"
  resources :sources, only: [ :index, :show ]
  resources :events, only: [ :show ]

  # Send an event again — the whole event, or one destination's delivery. Both
  # answer HTML for the inspector's buttons and JSON for scripts.
  post "events/:id/replay" => "replays#event", as: :replay_event
  post "deliveries/:id/replay" => "replays#delivery", as: :replay_delivery

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
