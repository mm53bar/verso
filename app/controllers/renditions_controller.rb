# Serves an artwork cropped to fill one display.
#
# Addressed by artwork and display rather than by storage key, so the URL is
# stable: the bytes behind it never change, and regenerating a variant does not
# hand a screen a new URL and make it swap for no reason.
#
# The bytes are streamed from here rather than redirected to. A redirect — to a
# storage service or even to Active Storage's own proxy route — costs a second
# round trip, cross-origin, on a device with a slow radio, at exactly the moment
# a screen is trying to swap. That is the latency the storage ADR is about, and
# it is easy to reintroduce by accident with a one-line `redirect_to`.
class RenditionsController < ApplicationController
  include PubliclyReadable
  include ActiveStorage::SetCurrent
  include ActiveStorage::Streaming

  def show
    artwork = Artwork.find_by!(slug: params[:artwork_slug])
    display = Display.find_by!(slug: params[:display_slug])

    return head :not_found unless artwork.original.attached?

    rendition = artwork.rendition_for(display).processed

    # Immutable by construction: this URL names one artwork at one size, so the
    # bytes behind it can never change.
    expires_in 1.year, public: true, immutable: true

    send_blob_stream rendition.image, disposition: :inline
  end
end
