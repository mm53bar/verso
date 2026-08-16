Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # What a screen should be showing. The only endpoint a screen ever calls —
  # see docs/adr/20260816-verso-owns-the-rotation.md.
  get "displays/:display_slug/current" => "feeds#show", as: :display_current, defaults: { format: :json }

  # A rendition, addressed by what it is rather than by where it is stored.
  # Stable per artwork and display: the bytes behind this URL never change, so
  # it can be cached hard, and regenerating a variant does not make a screen
  # swap for no reason. An Active Storage key in the URL would do both.
  get "artworks/:artwork_slug/renditions/:display_slug" => "renditions#show",
      as: :artwork_rendition, defaults: { format: :jpg }

  # The story page a wall screen frames: what is on that screen right now.
  # Separate from the browse UI on purpose — see the controller.
  get "kiosk/:display_slug" => "kiosk#show", as: :kiosk

  root "artworks#index"
  resources :artworks, only: %i[ index show ]
  resources :displays, only: %i[ index show ]
end
