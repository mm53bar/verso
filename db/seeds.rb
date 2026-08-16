# Seeds the shape of the collection, not its contents: the groupings artworks
# belong to and the screens verso drives. Artworks arrive over the API or
# through ArtworkImporter — see lib/tasks/import.rake.
#
# Idempotent, because bin/ci replants it on every run.

collections = {
  "Wikimedia canon" => {
    description: "Paintings ranked by how many language Wikipedias carry them.",
    weight: 1,
    minimum_aspect_ratio: 1.30
  },
  "Canadian — Group of Seven and circle" => {
    description: "Enumerated from Commons categories. Ranking by Wikidata sitelinks " \
                 "finds almost no Canadian art, so the canon method does not work here.",
    weight: 1,
    # A standard sketch panel is 8.5x10.5in. A 1.30 floor would discard most of
    # this body of work, which is why the floor belongs to the collection.
    minimum_aspect_ratio: 1.235
  },
  "Samsung Frame collection" => {
    description: "Chosen for the television, and natively 4K.",
    weight: 1,
    minimum_aspect_ratio: 1.30
  },
  "Cartoons" => {
    description: "Film, strip and book wallpapers. Weighted up so a small group " \
                 "is not diluted by a large one.",
    weight: 3,
    minimum_aspect_ratio: 1.30
  }
}.to_h do |name, attributes|
  collection = Collection.find_or_initialize_by(name: name)
  collection.update!(attributes)
  [ name, collection ]
end

# Two screens, two aspect ratios, one collection. Delivery differs because the
# clients differ — a browser can only poll, a cron script can only read a file —
# but the decision is verso's either way.
kiosk = Display.find_or_initialize_by(slug: "kiosk-panel")
kiosk.update!(
  name: "Kiosk panel", width: 1920, height: 1200,
  cycle_seconds: 30.minutes.to_i, delivery: "http", active: true
)

television = Display.find_or_initialize_by(slug: "television")
television.update!(
  name: "Television", width: 3840, height: 2160,
  cycle_seconds: 1.day.to_i, delivery: "file",
  # Relative to VERSO_DELIVERY_PATH, never an absolute path — see
  # docs/adr/20260816-filesystem-paths-are-configuration.md.
  file_path: "television/current.jpg", active: true
)

# The kiosk carries everything. The television carries the art, with the pieces
# bought for it weighted up, and no cartoons.
{
  kiosk => { "Wikimedia canon" => 1, "Canadian — Group of Seven and circle" => 1,
             "Samsung Frame collection" => 1, "Cartoons" => 3 },
  television => { "Wikimedia canon" => 1, "Canadian — Group of Seven and circle" => 1,
                  "Samsung Frame collection" => 2 }
}.each do |display, weights|
  weights.each do |name, weight|
    pairing = DisplayCollection.find_or_initialize_by(display: display, collection: collections.fetch(name))
    pairing.update!(weight: weight)
  end
end

puts "seeded #{Collection.count} collections and #{Display.count} displays"
