# What a screen should be showing, and what to preload next.
#
# This is the whole client contract. A screen asks and shows; it does not
# choose, shuffle, persist a cursor, or report back.
class FeedsController < ApplicationController
  include PubliclyReadable

  def show
    @display = Display.find_by!(slug: params[:display_slug])
    @artwork = @display.current_artwork
    @next_artwork = @display.next_artwork

    # The clock lives in the Display, because there are two kinds of it — an
    # interval and a time of day — and a client should not have to know which.
    # It asks how long the current piece has left and is told, on any schedule it
    # likes to poll on.
    @seconds_remaining = @display.seconds_remaining

    fresh_when(etag: [ @display, @artwork, @next_artwork ], last_modified: @display.current_since)
  end
end
