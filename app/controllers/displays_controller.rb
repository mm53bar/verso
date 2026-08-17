class DisplaysController < ApplicationController
  include SameOriginWrite

  def index
    @displays = Display.includes(:current_artwork, :collections).order(:name)
  end

  # Step the rotation on. The screens notice within a minute, when they next poll.
  def advance
    display = Display.find_by!(slug: params[:display_slug])
    artwork = display.advance!

    redirect_back fallback_location: display_path(display),
      notice: artwork ? "Now showing #{artwork.display_title}." :
                        "Nothing is eligible for #{display.name}."
  end

  # Put a chosen picture up. Applied to the leader, so followers are told too and
  # both rooms stay on the same artwork.
  def show_now
    display = Display.find_by!(slug: params[:display_slug])
    artwork = Artwork.find_by!(slug: params[:artwork_slug])
    display.show!(artwork)

    redirect_back fallback_location: artwork_path(artwork),
      notice: "Now showing #{artwork.display_title}."
  end

  def show
    @display = Display.find_by!(slug: params[:id])
    @eligible = @display.eligible_artworks.includes(:artist).count
    @recent = @display.display_events.recent.includes(artwork: :artist).limit(20)
  end
end
