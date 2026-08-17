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

# Two screens, two shapes, ONE rotation. The kiosk leads and the television
# follows, so both rooms show the same picture at the same time — which is what
# makes noticing a painting on the TV and reading about it on the kiosk work.
#
# They render it differently, and deliberately:
#
#   kiosk      fill    — it is a dashboard background behind a clock, and matte
#                        bars there would read as a broken image.
#   television contain — it is pretending to be a hanging painting. Cropping a
#                        Group of Seven sketch panel to 16:9 discards a third of
#                        the picture. Matting instead took the set both screens
#                        can share from 76 artworks to 117.
kiosk = Display.find_or_initialize_by(slug: "kiosk-panel")
kiosk.update!(
  name: "Kiosk panel", width: 1920, height: 1200,
  cycle_seconds: 1.hour.to_i, delivery: "http", render_mode: "fill", active: true
)

television = Display.find_or_initialize_by(slug: "television")
television.update!(
  name: "Television", width: 3840, height: 2160,
  cycle_seconds: 1.hour.to_i, delivery: "file", render_mode: "contain",
  matte_color: "#111111",
  # Relative to VERSO_DELIVERY_PATH, never an absolute path — see
  # docs/adr/20260816-filesystem-paths-are-configuration.md.
  file_path: "television/current.jpg", active: true,
  follows_display: kiosk
)

# Both screens carry everything. Because the leader may only pick what its
# followers can also render, what actually reaches a screen is decided by
# whether the picture is big enough — not by curation lists pulling in two
# directions.
[ kiosk, television ].each do |display|
  collections.each_value do |collection|
    pairing = DisplayCollection.find_or_initialize_by(display: display, collection: collection)
    # Weight only means anything on the leader; a follower is told what to show.
    # Cartoons are no longer boosted: the count that made boosting necessary has
    # dropped to the handful that are large enough for the 4K panel, and they
    # now appear in the living room as well as the kitchen.
    pairing.update!(weight: 1)
  end
end

puts "seeded #{Collection.count} collections and #{Display.count} displays"
