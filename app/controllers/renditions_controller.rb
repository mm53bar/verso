# Serves an artwork cropped to fill one display.
#
# Addressed by artwork and display rather than by storage key, so the URL is
# stable: the bytes behind it never change, and regenerating a variant does not
# hand a screen a new URL and make it swap for no reason.
#
# The bytes are served from here rather than redirected to. A redirect — to a
# storage service or even to Active Storage's own proxy route — costs a second
# round trip, cross-origin, on a device with a slow radio, at exactly the moment
# a screen is trying to swap. That is the latency the storage ADR is about, and
# it is easy to reintroduce by accident with a one-line `redirect_to`.
#
# BUFFERED, NOT STREAMED, AND THAT IS THE POINT OF THE CONTENT-LENGTH BELOW.
# `send_blob_stream` was the obvious choice and was wrong here. It pulls in
# ActionController::Live, whose Buffer deletes Content-Length on the first write
# — deliberately, since a streaming response cannot in general know its own
# length. The consequences were both visible from outside: every GET came back
# chunked with no length at all, and a HEAD answered `Content-Length: 0` for a
# rendition megabytes long, which is a wrong answer rather than a missing one.
# Anything sizing an image before fetching it, an uptime check included, reads
# that as an empty file.
#
# A rendition is a few hundred KB to a couple of MB and its size is known before
# the first byte moves, so buffering costs little and buys a real length, no
# chunk framing, and no thread-per-request from Live. Renditions only — an
# original in this collection runs to 717MB and must never be served this way.
class RenditionsController < ApplicationController
  include PubliclyReadable
  include ActiveStorage::SetCurrent

  def show
    artwork = Artwork.find_by!(slug: params[:artwork_slug])
    display = Display.find_by!(slug: params[:display_slug])

    return head :not_found unless artwork.original.attached?

    blob = artwork.rendition_for(display).processed.image

    # Immutable by construction: this URL names one artwork at one size, so the
    # bytes behind it can never change.
    expires_in 1.year, public: true, immutable: true

    # Set explicitly rather than left to the server. Rack::Head empties the body
    # of a HEAD before anything downstream counts it, so a length computed from
    # the body is 0 for exactly the request that asked only for the length.
    response.headers["Content-Length"] = blob.byte_size.to_s

    # A HEAD asks what a GET would answer, not for the bytes. Reading the whole
    # rendition off disk for Rack to discard is work nobody asked for.
    return head :ok, content_type: blob.content_type_for_serving if request.head?

    send_data blob.download,
      type: blob.content_type_for_serving,
      filename: blob.filename.sanitized,
      disposition: :inline
  end
end
