namespace :verso do
  desc "Import artworks from a JSON manifest: bin/rails 'verso:import[path/to/manifest.json]'"
  task :import, [ :manifest ] => :environment do |_task, args|
    path = args[:manifest]
    abort "usage: bin/rails 'verso:import[path/to/manifest.json]'" if path.blank?
    abort "no such manifest: #{path}" unless File.exist?(path)

    parsed = JSON.parse(File.read(path))
    records = parsed.is_a?(Hash) ? parsed.fetch("artworks") : parsed

    # A remote source that rate-limits wants seconds between requests, not
    # milliseconds. Raise this rather than lowering it if a run starts failing.
    delay = Integer(ENV.fetch("IMPORT_DELAY", 10))
    force = ENV["FORCE"].present?

    puts "importing #{records.length} records at #{delay}s between remote fetches#{force ? ' (forced)' : ''}"

    progress = lambda do |position, outcome, label, artwork|
      size = artwork&.width ? " #{artwork.width}x#{artwork.height}" : ""
      puts format("  %-9s %-9s%s %s", position, outcome, size, label)
      $stdout.flush
    end

    result = ArtworkImportBatch.new(records, delay: delay, force: force, progress: progress).call

    puts "\nimported #{result.imported}, skipped #{result.skipped}, failed #{result.failed}"

    if result.errors.any?
      puts "\nfailures:"
      result.errors.each { |error| puts "  #{error}" }
      puts "\nre-run the same command to retry only what is missing."
    end
  end
end

namespace :verso do
  desc "Rebuild the collection from an export directory: bin/rails 'verso:restore[/path/to/export]'"
  task :restore, [ :path ] => :environment do |_task, args|
    path = args[:path].presence || Verso.export_root
    manifest = Pathname.new(path).join(ArtworkExporter::MANIFEST)
    abort "no manifest at #{manifest}" unless manifest.exist?

    count = JSON.parse(manifest.read).fetch("count", "?")
    puts "restoring #{count} artworks from #{path}"

    results = ArtworkImporter.from_export(path)
    failed = results.reject(&:success?)

    puts "restored #{results.length - failed.length} of #{results.length}"
    failed.each { |result| puts "  failed: #{result.error}" }

    abort "restore incomplete" if failed.any?
  end
end
