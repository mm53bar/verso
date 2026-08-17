require "json"
require "digest"

# Writes the collection back out in a form that needs no verso at all: original
# images under human-readable names, plus a manifest carrying every field.
#
# This exists because Active Storage names blobs by random key, so its on-disk
# tree is unreadable and useless without the matching database. An operator who
# wants the pictures back should not need a running Rails app to get them —
# see docs/adr/20260816-active-storage-with-round-trippable-export.md.
#
# Originals only. Renditions are derivable by definition, and writing them would
# multiply the size of the backup without adding anything recoverable.
#
# ArtworkImporter.from_export reads what this writes, and a test asserts the
# round trip. That assertion is the point: an export nobody has restored from is
# a folder you believe in.
class ArtworkExporter
  MANIFEST = "manifest.json"
  VERSION = 1

  Result = Struct.new(:path, :written, :unchanged, :errors) do
    def success? = errors.empty?
    def total = written + unchanged
  end

  def initialize(path: Verso.export_root, scope: Artwork.all)
    @root = Pathname.new(path)
    @scope = scope
  end

  def call
    @root.mkpath
    written = 0
    unchanged = 0
    errors = []
    records = []

    artworks.find_each do |artwork|
      unless artwork.original.attached?
        errors << "#{artwork.slug}: no original attached, nothing to export"
        next
      end

      blob = artwork.original.blob
      name = filename_for(artwork, blob)

      if copy_original(blob, @root.join(name))
        written += 1
      else
        unchanged += 1
      end

      records << record_for(artwork, blob, name)
    rescue StandardError => e
      errors << "#{artwork.slug}: #{e.class}: #{e.message}"
    end

    write_manifest(records)

    Result.new(@root, written, unchanged, errors)
  end

  private
    # Ordered by slug so the manifest is byte-stable between runs that changed
    # nothing — a diff should show real changes, not reordering.
    def artworks
      @scope.includes(:artist, :collection, original_attachment: :blob).order(:slug)
    end

    def filename_for(artwork, blob)
      "#{artwork.slug}#{blob.filename.extension_with_delimiter}"
    end

    # True if bytes were written. Active Storage already stores a checksum, so
    # an unchanged original costs one hash of a local file rather than a copy.
    def copy_original(blob, destination)
      return false if destination.exist? && Digest::MD5.file(destination).base64digest == blob.checksum

      blob.open { |source| FileUtils.cp(source.path, destination) }
      true
    end

    def record_for(artwork, blob, name)
      {
        slug: artwork.slug,
        title: artwork.title,
        year_text: artwork.year_text,
        blurb: artwork.blurb,
        story: artwork.story,
        medium: artwork.medium,
        current_location: artwork.current_location,
        source: artwork.source,
        source_url: artwork.source_url,
        source_file: artwork.source_file,
        wikidata_qid: artwork.wikidata_qid,
        license: artwork.license,
        credit_line: artwork.credit_line,
        active: artwork.active,
        reviewed: artwork.reviewed,
        weight: artwork.weight,
        width: artwork.width,
        height: artwork.height,
        collection: collection_record(artwork.collection),
        artist: artist_record(artwork.artist),
        file: name,
        original_filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size,
        checksum: blob.checksum
      }
    end

    def collection_record(collection)
      {
        name: collection.name,
        slug: collection.slug,
        description: collection.description,
        minimum_aspect_ratio: collection.minimum_aspect_ratio&.to_s,
        max_upscale: collection.max_upscale.to_s
      }
    end

    def artist_record(artist)
      return if artist.nil?

      {
        name: artist.name,
        slug: artist.slug,
        birth_year: artist.birth_year,
        death_year: artist.death_year,
        nationality: artist.nationality,
        bio: artist.bio
      }
    end

    def write_manifest(records)
      payload = {
        version: VERSION,
        exported_at: Time.current.iso8601,
        count: records.length,
        artworks: records
      }

      @root.join(MANIFEST).write(JSON.pretty_generate(payload) + "\n")
    end
end
