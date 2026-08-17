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

namespace :verso do
  # Run this politely. It is maintenance, and it must never make the app worse
  # than not running it at all:
  #
  #   docker exec verso-verso-1 nice -n 19 bin/rails verso:warm
  #
  # Without the nice, a backfill saturates every core and a browse page that
  # normally takes 1.6s took over two minutes. VIPS_CONCURRENCY in compose caps
  # how much of the machine one image can claim; the nice decides who loses when
  # they compete.
  desc "Pre-generate every thumbnail and display rendition: bin/rails verso:warm"
  task warm: :environment do
    total = Artwork.count
    done = 0
    Artwork.find_each.with_index(1) do |artwork, i|
      done += artwork.warm_derivatives!
      puts "  #{i}/#{total} #{artwork.slug}"
      $stdout.flush
    rescue StandardError => e
      puts "  #{i}/#{total} FAILED #{artwork.slug}: #{e.class}"
    end
    puts "warmed #{done} derivatives"
  end
end

namespace :verso do
  desc "Fill in what Wikidata knows — where a work hangs, its medium, its date"
  task enrich: :environment do
    scope = Artwork.where.not(wikidata_qid: [ nil, "" ])
    puts "looking up #{scope.count} artworks with a Wikidata id"

    facts = WikidataLookup.facts_for(scope.pluck(:wikidata_qid))
    puts "  Wikidata answered for #{facts.size}"

    filled = Hash.new(0)
    scope.find_each do |artwork|
      known = facts[artwork.wikidata_qid]
      next if known.nil?

      # Only fill blanks. Anything already recorded was set deliberately, and a
      # bulk job should not quietly overwrite a human's correction. FORCE=1
      # re-derives the fields this task owns, for when the derivation improves.
      artwork.update!(current_location: nil, medium: nil) if ENV["FORCE"].present?
      updates = {}
      updates[:current_location] = known.housed_at if artwork.current_location.blank? && known.housed_at.present?
      updates[:medium]           = known.medium    if artwork.medium.blank? && known.medium.present?
      updates[:year_text]        = known.year      if artwork.year_text.blank? && known.year.present?
      updates[:source_url]       = known.article   if artwork.source_url.blank? && known.article.present?
      next if updates.empty?

      artwork.update!(updates)
      updates.each_key { |field| filled[field] += 1 }
    end

    filled.each { |field, n| puts "  filled #{field}: #{n}" }
    puts "  artworks now knowing where they hang: " \
         "#{Artwork.where.not(current_location: [ nil, '' ]).count} of #{Artwork.count}"
  end
end

namespace :verso do
  desc "Write each artwork's story from its own Wikipedia article"
  task stories: :environment do
    scope = Artwork.where.not(wikidata_qid: [ nil, "" ])
    scope = scope.where(story: [ nil, "" ]) unless ENV["FORCE"].present?
    puts "looking for stories for #{scope.count} artworks"

    # Wikidata knows the canonical article for each work. Guessing a title from
    # the artwork's own name lands on disambiguation pages.
    articles = WikidataLookup.facts_for(scope.pluck(:wikidata_qid))
      .transform_values(&:article).compact

    titles = articles.transform_values { |url| CGI.unescape(url.split("/").last).tr("_", " ") }
    puts "  #{titles.size} have an English Wikipedia article"

    stories = WikipediaStory.for(titles.values)
    puts "  #{stories.size} yielded a story worth showing"

    written = 0
    scope.find_each do |artwork|
      title = titles[artwork.wikidata_qid]
      story = title && stories[title]
      next if story.nil?

      artwork.update!(story: story.text, story_source_url: story.url,
                      story_source_name: "Wikipedia")
      written += 1
    end

    puts "  wrote #{written} stories"
    puts "  artworks with a story: #{Artwork.where.not(story: [ nil, '' ]).count} of #{Artwork.count}"
  end
end

namespace :verso do
  desc "What the catalogue is missing, per collection"
  task coverage: :environment do
    scope = Artwork.where(active: true, reviewed: true)

    puts "#{scope.count} artworks can reach a screen. Of those:"
    {
      "blurb (spoken)" => :blurb,
      "story (read)" => :story,
      "title" => :title,
      "year" => :year_text,
      "where it hangs" => :current_location
    }.each do |label, column|
      have = scope.where.not(column => [ nil, "" ]).count
      puts format("  %-16s %3d of %3d", label, have, scope.count)
    end

    # A blurb is what a voice assistant reads out, so a missing one is not a
    # thinner answer, it is no answer at all when that artwork happens to be up.
    missing = scope.where(blurb: [ nil, "" ]).order(:title)
    if missing.any?
      puts "\nno blurb, so voice has nothing to say when these are showing:"
      missing.each { |a| puts "  #{a.slug}" }
    end

    # These read badly aloud. Piper says punctuation it cannot interpret, and HA
    # cannot pace a long passage, so both are caught here rather than by ear.
    unspeakable = scope.where.not(blurb: [ nil, "" ]).select do |a|
      a.blurb.match?(/[–—×]|\bc\.\s*\d/) || a.blurb.length > 320
    end
    if unspeakable.any?
      puts "\nblurbs that will not survive being spoken:"
      unspeakable.each { |a| puts "  #{a.slug}: #{a.blurb[0, 60]}" }
    end
  end
end
