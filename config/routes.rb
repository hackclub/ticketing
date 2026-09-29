Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  resources :tickets, only: [ :index, :new, :create, :show, :update ] do
    resources :notes, only: [ :create, :destroy ], controller: "ticket_notes"
    resources :blocks, only: [ :create, :destroy ], controller: "ticket_blocks"
    resource :deadline, only: [ :update, :destroy ], controller: "ticket_deadlines"
  end

  # Backs the ⌘K palette. GET so a result list is just a page.
  get "/search", to: "search#index", as: :search

  # Services and topics are managed together on the services page, so there
  # are no standalone "new" screens. They belong to whoever takes the tickets
  # filed under them, which is why they aren't admin-only.
  resources :services, except: [ :new, :show ]
  resources :topics, only: [ :create, :edit, :update, :destroy ]

  namespace :admin do
    resources :users, only: [ :index, :show, :update ]
  end

  post "/mcp", to: "mcp#create", as: :mcp
  match "/mcp", to: "mcp#unsupported", via: [ :get, :delete ]

  # OAuth, so MCP clients that can't send a custom header (Claude's connector
  # UI, for one) can still authenticate. Discovery paths are fixed by spec.
  get "/.well-known/oauth-protected-resource", to: "well_known#protected_resource"
  get "/.well-known/oauth-protected-resource/mcp", to: "well_known#protected_resource"
  get "/.well-known/oauth-authorization-server", to: "well_known#authorization_server"
  get "/.well-known/oauth-authorization-server/mcp", to: "well_known#authorization_server"

  namespace :oauth do
    post "register", to: "clients#create"
    get "authorize", to: "authorizations#new"
    post "authorize", to: "authorizations#create"
    post "token", to: "tokens#create"
    post "revoke", to: "tokens#revoke"
  end

  resource :settings, only: [ :show ] do
    post :api_token
    delete :api_token, action: :revoke_api_token
    delete "connections/:id", action: :revoke_connection, as: :connection
  end

  namespace :slack do
    post "interactions", to: "interactions#create"
    post "events", to: "events#create"
  end

  get "/auth/:provider/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "/logout", to: "sessions#destroy"
end
