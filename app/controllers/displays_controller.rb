class DisplaysController < ApplicationController
  def index
    @displays = Display.includes(:current_artwork, :collections).order(:name)
  end

  def show
    @display = Display.find_by!(slug: params[:id])
    @eligible = @display.eligible_artworks.includes(:artist).count
    @recent = @display.display_events.recent.includes(artwork: :artist).limit(20)
  end
end
