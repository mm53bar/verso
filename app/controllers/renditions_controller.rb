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

    blob = artwork.rendition_for(display).processed.image

    # Immutable by construction: this URL names one artwork at one size, so the
    # bytes behind it can never change.
    expires_in 1.year, public: true, immutable: true

    # A streamed response carries no Content-Length, because in general the
    # length is not known until the last chunk. Here it is known exactly before
    # the first one, and saying so is worth doing: without it a HEAD reported
    # `Content-Length: 0` for a rendition megabytes long, which is not a missing
    # answer but a wrong one -- anything sizing the image before fetching it, an
    # uptime check included, reads that as an empty file.
    response.headers["Content-Length"] = blob.byte_size.to_s

    # A HEAD asks what a GET would answer, not for the bytes. Letting it fall
    # through to send_blob_stream reads the whole rendition off disk so that Rack
    # can throw the body away.
    return head :ok, content_type: blob.content_type_for_serving if request.head?

    send_blob_stream blob, disposition: :inline
  end
end
