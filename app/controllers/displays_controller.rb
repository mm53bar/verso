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

  # Change when a screen rotates, and whether it decides for itself.
  #
  # An ordinary same-origin form post, like the other two writes here — see
  # SameOriginWrite. Nothing scripted, so none of this touches the CORS surface.
  def update_schedule
    display = Display.find_by!(slug: params[:display_slug])

    if display.update(schedule_params)
      redirect_to settings_path, notice: "#{display.name}: #{display.schedule_description}."
    else
      redirect_to settings_path,
        alert: "#{display.name}: #{display.errors.full_messages.to_sentence}."
    end
  end

  def show
    @display = Display.find_by!(slug: params[:id])
    @eligible = @display.eligible_artworks.includes(:artist).count
    @recent = @display.display_events.recent.includes(artwork: :artist).limit(20)
  end

  private
    # "Every so often" and "once a day at" are one choice with two shapes, so the
    # form sends which shape it means and the unused half is cleared. Left behind,
    # a stale rotate_at would go on overruling the interval the operator just
    # picked, silently, because daily? only asks whether the column is present.
    def schedule_params
      permitted = params.expect(display: [ :cycle_seconds, :rotate_at, :follows_display_id ])

      params[:display][:schedule_kind] == "daily" ? permitted : permitted.merge(rotate_at: nil)
    end
end
