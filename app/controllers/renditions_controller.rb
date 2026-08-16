# Serves an artwork cropped to fill one display.
#
# Addressed by artwork and display rather than by storage key, so the URL is
# stable: the bytes behind it never change, and regenerating a variant does not
# hand a screen a new URL and make it swap for no reason.
class RenditionsController < ApplicationController
  include PubliclyReadable

  # Images used as CSS backgrounds need no CORS at all, but the header costs
  # nothing and a future client may want to read one through script.
  def show
    artwork = Artwork.find_by!(slug: params[:artwork_slug])
    display = Display.find_by!(slug: params[:display_slug])

    head :not_found and return unless artwork.original.attached?

    rendition = artwork.rendition_for(display).processed

    # Immutable by construction: this URL identifies one artwork at one size.
    expires_in 1.year, public: true, immutable: true

    redirect_to rails_storage_proxy_url(rendition), allow_other_host: true
  end
end
