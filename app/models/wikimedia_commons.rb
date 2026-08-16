require "digest"
require "erb"

# Turns a Wikimedia Commons filename into the URLs its bytes are served from.
#
# Commons shards uploads by the MD5 of the underscored filename: the first hex
# digit, then the first two. There is no lookup involved — the path is derivable,
# which is why an import needs only the filename.
#
# Two traps, both learned the expensive way:
#
# - Thumbnails are served at 960, 1280, 1920 and 3840 px only. Any other width
#   is a hard 400 forever, no matter how slowly you ask. An early attempt read
#   those failures as rate limiting and lost an hour to it.
# - There is a real per-IP rate limit on top, and it is much harsher on
#   originals than on thumbnails, which are CDN-cached. Measured 2026-08-16:
#   thumbnails survived four requests at 2.5s spacing, originals were refused
#   after one. Pace originals in seconds, not milliseconds, and expect 429.
class WikimediaCommons
  BASE = "https://upload.wikimedia.org/wikipedia/commons".freeze

  # The only widths Commons will render. Not a preference — anything else 400s.
  THUMBNAIL_WIDTHS = [ 960, 1280, 1920, 3840 ].freeze

  class UnsupportedWidth < ArgumentError; end

  def initialize(source_file)
    @name = source_file.to_s.tr(" ", "_")
  end

  def original_url
    "#{BASE}/#{shard}/#{escaped}"
  end

  def thumbnail_url(width)
    unless THUMBNAIL_WIDTHS.include?(width)
      raise UnsupportedWidth, "Commons serves #{THUMBNAIL_WIDTHS.to_sentence} px only, not #{width}"
    end

    "#{BASE}/thumb/#{shard}/#{escaped}/#{width}px-#{escaped}"
  end

  def page_url
    "https://commons.wikimedia.org/wiki/File:#{escaped}"
  end

  private
    def shard
      digest = Digest::MD5.hexdigest(@name)

      "#{digest[0]}/#{digest[0, 2]}"
    end

    def escaped
      ERB::Util.url_encode(@name)
    end
end
