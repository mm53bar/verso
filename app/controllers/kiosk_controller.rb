# The story page a wall screen frames: what is on that screen right now, and
# what is known about it.
#
# Built for counter distance on a small viewport rather than reusing the browse
# UI — the kiosk's CSS viewport is 854x534 at dpr 1.5, so type and targets that
# read fine on a laptop are far too small here.
class KioskController < ApplicationController
  layout "kiosk"

  def show
    @display = Display.find_by!(slug: params[:display_slug])
    @artwork = @display.current_artwork
    @artist  = @artwork&.artist
    @back    = safe_back_path
  end

  private
    # The framing dashboard passes where "back" should go, because verso does
    # not know how that dashboard is laid out. Only same-site absolute paths are
    # honoured: anything else — a scheme, a host, a javascript: URL — would turn
    # a query parameter into an open redirect on a page with no authentication.
    def safe_back_path
      candidate = params[:back].to_s

      candidate if candidate.match?(%r{\A/[^/\\]}) && !candidate.include?("://")
    end
end
