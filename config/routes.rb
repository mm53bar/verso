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
  #
  # The format is NOT defaulted here. A `defaults: { format: :jpg }` makes Rails
  # leave the extension out of every URL it generates, since it matches the
  # default -- so callers asking for `format: :jpg` silently got an
  # extensionless URL. Clients are meant to be dumb, and an extensionless image
  # URL asks them to be clever: one of them refused the image outright rather
  # than read the Content-Type. Callers pass the extension explicitly, and
  # Display#rendition_extension is where it comes from.
  get "artworks/:artwork_slug/renditions/:display_slug" => "renditions#show",
      as: :artwork_rendition

  # The browse UI's images, on the same terms as a rendition: addressed by
  # artwork and size, not by storage key.
  #
  # These used to be Active Storage proxy URLs, generated straight from
  # `image_tag artwork.thumbnail`. Two things were wrong with that. The URL
  # carried a signed variant key, so regenerating a variant changed every URL on
  # the page -- the brief warned about precisely this. And Active Storage's proxy
  # controller includes ActionController::Live: measured on the index, a 40KB
  # thumbnail had a p90 of 516ms and a tail of 2.4s, against a flat 165ms for
  # 2.3MB through the controller that does not stream.
  get "artworks/:artwork_slug/variants/:variant" => "renditions#variant",
      as: :artwork_variant, constraints: { variant: /thumb|tile|detail/ }

  # Choosing a picture by hand, and stepping the rotation on. Both are ordinary
  # same-origin form posts rather than anything scripted, which is what keeps
  # them off the CORS surface entirely — see
  # docs/adr/20260816-cors-on-the-feed-routes.md. The kiosk page these buttons
  # live on is served by verso and merely framed by Home Assistant, so a form in
  # it posts back to verso's own origin.
  post "artworks/:artwork_slug/favourite" => "artworks#favourite", as: :favourite_artwork
  post "displays/:display_slug/advance" => "displays#advance", as: :advance_display
  post "displays/:display_slug/show/:artwork_slug" => "displays#show_now",
       as: :show_artwork_on_display

  # The story page a wall screen frames: what is on that screen right now.
  # Separate from the browse UI on purpose — see the controller.
  get "kiosk/:display_slug" => "kiosk#show", as: :kiosk

  root "artworks#index"
  resources :artworks, only: %i[ index show ]
  resources :displays, only: %i[ index show ]
end
