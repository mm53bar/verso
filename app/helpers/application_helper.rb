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
end
