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

    # The clock lives here, so a client can poll on any schedule it likes and
    # still know how long the current piece has left.
    @seconds_remaining = seconds_remaining

    fresh_when(etag: [ @display, @artwork, @next_artwork ], last_modified: @display.current_since)
  end

  private
    def seconds_remaining
      return 0 if @display.current_since.nil?

      elapsed = Time.current - @display.current_since
      [ (@display.cycle_seconds - elapsed).ceil, 0 ].max
    end
end
