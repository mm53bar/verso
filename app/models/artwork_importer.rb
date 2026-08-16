require "open-uri"
require "json"

# Brings one artwork into verso: its metadata, its artist and collection, and
# the original image bytes at whatever resolution the source offers.
#
# Bytes come from one of three places, in this order of preference:
#
#   io:          already-open bytes. Used by the export round trip, and by
#                tests, which inject at the real dependency rather than through
#                a mocking library.
#   image_path:  a file on disk.
#   image_url:   fetched over HTTP, with retries.
#
# The retries are not decoration. Building the original collection produced 8
# of 44 files once, and the cause turned out to be a missing retry loop rather
# than the rate limiting it was mistaken for.
class ArtworkImporter
  Result = Struct.new(:artwork, :error) do
    def success? = error.nil?
  end

  USER_AGENT = "verso-importer"
  MAX_ATTEMPTS = 4

  # Fields an importer may set. Anything else in the payload is ignored, so a
  # source carrying its own bookkeeping (a fame ranking, a crop flag) does not
  # have to be stripped first. Dimensions are deliberately absent: they are read
  # from the image itself, never taken on trust.
  FIELDS = %w[
    title year_text blurb story medium current_location
    source source_url source_file wikidata_qid license credit_line
    active reviewed weight
  ].freeze

  # backoff: seconds to wait before retry N. Injectable so tests can exercise
  # the retry path without actually sleeping.
  def initialize(attributes, io: nil, backoff: ->(attempt) { 2**attempt })
    @attributes = attributes.to_h.with_indifferent_access
    @io = io
    @backoff = backoff
    @error = nil
  end

  def call
    collection = resolve_collection
    return Result.new(nil, "collection is required") if collection.nil?

    artwork = find_or_initialize
    artwork.assign_attributes(@attributes.slice(*FIELDS))
    artwork.collection = collection
    artwork.artist = resolve_artist
    artwork.save!

    bytes = open_bytes
    return Result.new(nil, @error) if bytes.nil?

    artwork.original.attach(io: bytes, filename: filename, content_type: @attributes[:content_type])
    artwork.record_dimensions!

    Result.new(artwork, nil)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(nil, e.record.errors.full_messages.to_sentence)
  ensure
    # Close only what this object opened. An injected io belongs to the caller.
    bytes.close if bytes && bytes != @io && !bytes.closed?
  end

  # Rebuild a collection from a directory ArtworkExporter wrote. This is the
  # other half of the promise that the images are not trapped in verso — see
  # docs/adr/20260816-active-storage-with-round-trippable-export.md — and the
  # reason a round trip can be asserted in a test rather than believed.
  def self.from_export(path)
    root = Pathname.new(path)
    manifest = JSON.parse(root.join(ArtworkExporter::MANIFEST).read)

    manifest.fetch("artworks").map do |record|
      file = root.join(record.fetch("file"))

      File.open(file) do |io|
        new(record, io: io).call
      end
    end
  end

  private
    # An explicit slug means "this is that artwork" — the export carries one, so
    # re-importing updates in place and the round trip is exact. Without one,
    # every import is a new record and the slug is derived.
    def find_or_initialize
      slug = @attributes[:slug]

      slug.present? ? Artwork.find_or_initialize_by(slug: slug) : Artwork.new
    end

    def resolve_collection
      name, attributes = name_and_attributes(@attributes[:collection])
      return if name.blank?

      Collection.find_or_create_by!(name: name) do |collection|
        collection.assign_attributes(attributes.slice("description", "weight", "minimum_aspect_ratio"))
      end
    end

    # Optional, and permanently so for the pieces whose maker is unknown and the
    # ones that never had a single author.
    def resolve_artist
      name, attributes = name_and_attributes(@attributes[:artist])
      return if name.blank?

      Artist.find_or_create_by!(name: name) do |artist|
        artist.assign_attributes(attributes.slice("birth_year", "death_year", "nationality", "bio"))
      end
    end

    # Accepts either a bare name or a full nested record, so a thin source and
    # an export manifest can both be fed to the same importer.
    def name_and_attributes(value)
      case value
      when Hash            then [ value["name"], value ]
      when String, Symbol  then [ value.to_s, {} ]
      else [ nil, {} ]
      end
    end

    def open_bytes
      return @io if @io

      if @attributes[:image_path].present?
        open_path(@attributes[:image_path])
      elsif @attributes[:image_url].present?
        fetch(@attributes[:image_url])
      else
        @error = "no image source given (io, image_path or image_url)"
        nil
      end
    end

    def open_path(path)
      File.open(path)
    rescue SystemCallError => e
      @error = "couldn't read #{path}: #{e.class}"
      nil
    end

    def fetch(url)
      uri = URI.parse(url.to_s)
      unless %w[http https].include?(uri.scheme)
        @error = "image_url must be http or https"
        return nil
      end

      attempt = 0
      begin
        attempt += 1
        URI.open(uri, "User-Agent" => USER_AGENT, redirect: true, read_timeout: 30)
      rescue StandardError => e
        if attempt < MAX_ATTEMPTS
          sleep @backoff.call(attempt)
          retry
        end
        @error = "couldn't fetch #{uri} after #{MAX_ATTEMPTS} attempts: #{e.class}"
        nil
      end
    rescue URI::InvalidURIError
      @error = "image_url is not a valid URL"
      nil
    end

    def filename
      @attributes[:original_filename].presence ||
        @attributes[:file].presence ||
        File.basename(URI.parse(@attributes[:image_url].to_s).path.presence || "original.jpg")
    rescue URI::InvalidURIError
      "original.jpg"
    end
end
