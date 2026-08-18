module ApplicationHelper
  # The URL for one of an artwork's named sizes.
  #
  # The extension is always .jpg because every named variant is declared with
  # `format: :jpeg` in Artwork, and it is spelled out rather than defaulted on the
  # route: a `defaults: { format: :jpg }` makes Rails omit the extension from
  # every URL it generates, which is how a rendition URL once reached the Frame
  # with no extension and was refused outright.
  def artwork_variant_url_for(artwork, size)
    artwork_variant_path(artwork.slug, size, format: :jpg)
  end

  # A rendition URL, carrying a fingerprint of the bytes behind it.
  #
  # The path stays stable per artwork and display; the `v` param changes only when
  # the image actually changes. That keeps the `immutable` cache header honest
  # rather than abandoning it — a screen re-fetches when there is something new
  # and never otherwise. RenditionsController ignores `v`, so an older URL still
  # serves, which matters for a page a kiosk rendered an hour ago.
  def artwork_rendition_url_for(artwork, display)
    artwork_rendition_url(artwork.slug, display.slug,
      format: display.rendition_extension, v: artwork.rendition_fingerprint(display))
  end

  def artwork_rendition_path_for(artwork, display)
    artwork_rendition_path(artwork.slug, display.slug,
      format: display.rendition_extension, v: artwork.rendition_fingerprint(display))
  end
end
