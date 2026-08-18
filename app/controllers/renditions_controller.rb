# Serves an artwork's bytes: cropped to fill one display, or at one of the sizes
# the browse UI asks for by name.
#
# Addressed by artwork and size rather than by storage key, so the URL is stable:
# the bytes behind it never change, and regenerating a variant does not hand a
# screen or a page a new URL and make it fetch again for no reason.
#
# The bytes are served from here rather than redirected to. A redirect — to a
# storage service or even to Active Storage's own proxy route — costs a second
# round trip, cross-origin, on a device with a slow radio, at exactly the moment
# a screen is trying to swap. That is the latency the storage ADR is about, and
# it is easy to reintroduce by accident with a one-line `redirect_to`.
#
# HAND THE PROXY A PATH; DO NOT STREAM, AND DO NOT BUFFER IF A PATH WILL DO.
# Three ways to answer with an image, and this app has now been bitten by two of
# them:
#
#   send_blob_stream  pulls in ActionController::Live, whose Buffer deletes
#                     Content-Length on the first write. Every GET came back
#                     chunked with no length, and a HEAD answered 0 for a file
#                     megabytes long, which is a wrong answer rather than a
#                     missing one. It also hands the body to a second thread that
#                     checks out its own database connection, and it is slow:
#                     measured p90 516ms and a 2.4s tail for a 40KB thumbnail.
#   send_data         reads the whole file into a String first. Correct, and
#                     honest about its length, but Ruby carries every byte.
#   send_file         hands Rack a path. In production Rack::Sendfile turns that
#                     into `X-Sendfile: /path` with an empty body and Thruster
#                     serves the file itself, so Puma is released at the headers.
#
# So: send_file when the blob is a real file on disk, send_data when it is not.
# The fallback is not decoration — `path_for` exists on the Disk service and
# nowhere else, so this degrades to buffering the day storage moves to S3 rather
# than raising in production. Never serve an ORIGINAL by either route; the
# largest in this collection is 717MB.
class RenditionsController < ApplicationController
  include PubliclyReadable
  include ActiveStorage::SetCurrent

  # The sizes a caller may name. Declared in Artwork, listed again here because
  # this is the boundary: anything else is a 404 rather than an invitation to
  # generate arbitrary variants of a gigapixel original on demand.
  NAMED_VARIANTS = %w[ thumb tile detail ].freeze

  def show
    artwork = artwork!
    display = Display.find_by!(slug: params[:display_slug])

    return head :not_found unless artwork.original.attached?

    serve artwork.rendition_for(display)
  end

  def variant
    artwork = artwork!

    return head :not_found unless NAMED_VARIANTS.include?(params[:variant])
    return head :not_found unless artwork.original.attached?

    serve artwork.original.variant(params[:variant].to_sym)
  end

  private
    def artwork!
      Artwork.find_by!(slug: params[:artwork_slug])
    end

    def serve(variant)
      blob = variant.processed.image

      # Immutable by construction: this URL names one artwork at one size, so the
      # bytes behind it can never change.
      expires_in 1.year, public: true, immutable: true

      # Set explicitly rather than left to the server. Rack::Head empties the body
      # of a HEAD before anything downstream counts it, so a length computed from
      # the body is 0 for exactly the request that asked only for the length.
      response.headers["Content-Length"] = blob.byte_size.to_s

      # A HEAD asks what a GET would answer, not for the bytes. This returns
      # before send_file, deliberately: Rack::Sendfile rewrites Content-Length to
      # 0 and lets the proxy restate it from the file, which is right for a GET
      # and would throw away the only answer a HEAD has.
      return head :ok, content_type: blob.content_type_for_serving if request.head?

      options = { type: blob.content_type_for_serving,
                  filename: blob.filename.sanitized, disposition: :inline }

      if (path = disk_path_for(blob))
        send_file path, **options
      else
        send_data blob.download, **options
      end
    end

    # The blob as a path the proxy can open, or nil if it is not one.
    #
    # Checked rather than assumed on both counts. `path_for` is Disk-service
    # only, and a missing file has to fall through to a download instead of
    # handing Rack a path that resolves to nothing — Rack::Sendfile does not stat
    # it, so the proxy would answer an empty 200.
    def disk_path_for(blob)
      service = blob.service
      return nil unless service.respond_to?(:path_for)

      path = service.path_for(blob.key)
      path if File.exist?(path)
    end
end
