# Runs a list of records through ArtworkImporter at a pace a remote source will
# tolerate, and survives being interrupted.
#
# Both properties matter for the same reason. Wikimedia Commons rate-limits per
# IP, harder on originals than on CDN-cached thumbnails, so a real import is
# measured in tens of minutes. Anything that takes tens of minutes will be
# interrupted eventually, and re-fetching two hundred images because the run
# died at number ninety is the kind of thing that gets a migration abandoned.
#
# Resumability comes from the slug: a record carrying one that already names an
# artwork with an attachment is skipped. Give the records stable slugs and a
# re-run costs nothing for the work already done.
class ArtworkImportBatch
  Result = Struct.new(:imported, :skipped, :failed, :errors) do
    def success? = errors.empty?
    def total = imported + skipped + failed
  end

  # delay: seconds between *remote* fetches. Local files are not paced — there
  # is nothing to be polite to.
  def initialize(records, delay: 10, force: false, progress: nil, sleeper: method(:sleep))
    @records = records.map { |record| record.to_h.with_indifferent_access }
    @delay = delay
    @force = force
    @progress = progress || ->(*) { }
    @sleeper = sleeper
  end

  def call
    imported = 0
    skipped = 0
    failed = 0
    errors = []
    remote_fetches = 0

    @records.each_with_index do |record, index|
      position = "#{index + 1}/#{@records.length}"

      if skip?(record)
        skipped += 1
        @progress.call(position, :skipped, label(record), nil)
        next
      end

      # Pace before the request, not after, so an interrupted run does not owe
      # the next one a delay.
      @sleeper.call(@delay) if remote?(record) && remote_fetches.positive?
      remote_fetches += 1 if remote?(record)

      result = ArtworkImporter.new(record, backoff: backoff, sleeper: @sleeper).call

      if result.success?
        imported += 1
        @progress.call(position, :imported, label(record), result.artwork)
      else
        failed += 1
        errors << "#{label(record)}: #{result.error}"
        @progress.call(position, :failed, label(record), nil)
      end
    end

    Result.new(imported, skipped, failed, errors)
  end

  private
    # Already here, with bytes. A record with no slug can never be recognised,
    # so it is always imported.
    def skip?(record)
      return false if @force
      return false if record[:slug].blank?

      Artwork.find_by(slug: record[:slug])&.original&.attached? || false
    end

    def remote?(record) = record[:image_url].present?

    def label(record) = record[:slug].presence || record[:title].presence || record[:source_file].to_s

    # Retries escalate from the configured pace rather than from a fixed base,
    # so raising the delay for a hostile source raises its retries too.
    def backoff
      ->(attempt) { @delay * (2**attempt) }
    end
end
