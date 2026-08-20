# Seeds the shape of the collection, not its contents: the groupings artworks
# belong to and the screens verso drives. Artworks arrive over the API or
# through ArtworkImporter — see lib/tasks/import.rake.
#
# Idempotent, because bin/ci replants it on every run.

collections = {
  "Wikimedia canon" => {
    description: "Paintings ranked by how many language Wikipedias carry them.",
    minimum_aspect_ratio: 1.30
  },
  "Canadian — Group of Seven and circle" => {
    description: "Enumerated from Commons categories. Ranking by Wikidata sitelinks " \
                 "finds almost no Canadian art, so the canon method does not work here.",
    # A standard sketch panel is 8.5x10.5in. A 1.30 floor would discard most of
    # this body of work, which is why the floor belongs to the collection.
    minimum_aspect_ratio: 1.235
  },
  "Samsung Frame collection" => {
    description: "Chosen for the television, and natively 4K.",
    minimum_aspect_ratio: 1.30
  },
  "Landscape and marine" => {
    description: "Found by asking which painters worked WIDE, since that is what " \
                 "survives a 16:9 window. Of 2571 paintings across thirteen artists, 82 " \
                 "fit. Winslow Homer alone supplied 24 of them, because watercolour on " \
                 "paper is habitually horizontal where stretched canvas is not.",
    minimum_aspect_ratio: 1.60
  },
  "Museums we have visited" => {
    description: "Chosen twice over: from the Louvre, the Rijksmuseum and the Van Gogh " \
                 "Museum, and only where the picture fits a 16:9 screen without being " \
                 "cropped to pieces. In practice that means Dutch and Flemish landscape, " \
                 "because that is the work that was painted wide.",
    # The sourcing floor, recorded rather than enforced: candidates were taken from
    # the television's own window, 1.6 to 1.975.
    minimum_aspect_ratio: 1.60
  },
  "Cartoons" => {
    description: "Film, strip and book wallpapers. Weighted up so a small group " \
                 "is not diluted by a large one.",
    minimum_aspect_ratio: 1.30,
    # The only collection allowed to be enlarged, and the reason is the material.
    # Cel and watercolour art is flat colour bounded by line, so 2x invents
    # almost nothing and is invisible across a room; the same treatment of a
    # photographed oil painting looks like an upscale. Without this the 4K
    # television is the binding constraint and cartoon wallpapers at native
    # 3840x2160 barely exist, which left 6 of 8 deactivated.
    max_upscale: 2.0
  }
}.to_h do |name, attributes|
  collection = Collection.find_or_initialize_by(name: name)
  collection.update!(attributes)
  [ name, collection ]
end

# Two screens, two shapes, two clocks. Both crop to fill — see
# docs/adr/20260817-fit-the-screen-not-the-art.md, which reversed the matting the
# television briefly had.
#
# They ran as ONE rotation until 2026-08-19: the kiosk led, the television
# followed, and both rooms showed the same picture, so noticing a painting on the
# TV and reading about it on the kiosk worked. What ended that is not a change of
# mind about the idea. Delivering an artwork to a Frame TV takes it out of
# whatever is on screen and switches it to art mode, so an hourly rotation
# interrupted a show hourly. The television now changes once a day overnight, and
# "once a day at 3am" cannot be said as an interval at all — see
# docs/adr/20260819-a-clock-for-the-television.md.
#
# SCHEDULE FIELDS ARE SEEDED ONCE AND NEVER RE-SEEDED. cycle_seconds, rotate_at
# and follows_display are assigned here only when the row is created, because
# they are editable at /settings and this file runs on every deploy.
# max_crop_fraction below is the standing example of what the other arrangement
# costs: a reviewed figure that a re-seed silently restores to whatever is
# written here.

# Sized to the panel, not above it. The Echo Show 8 is physically 1280x800 (a
# CSS viewport of 854x534 at dpr 1.5), so a 1920x1200 rendition was 1049KB where
# 1280x800 is 450KB — 2.3x the bytes for pixels the device cannot display, sent
# over wifi to a slow decoder every cycle.
#
# A screen of a different size is a new row, not a new size here: an Echo Show 5
# is 960x480, a different aspect ratio again, and gets its own Display.
kiosk = Display.find_or_initialize_by(slug: "kiosk-panel")
kiosk.assign_attributes(cycle_seconds: 1.hour.to_i) if kiosk.new_record?
kiosk.update!(
  name: "Kiosk panel", width: 1280, height: 800,
  delivery: "http", render_mode: "fill", active: true
)

television = Display.find_or_initialize_by(slug: "television")
if television.new_record?
  # Overnight, and on the wall clock rather than on an interval: a television is
  # watched at particular hours, so WHEN it changes is the requirement. Nobody is
  # watching at 3am, and an anchored time cannot drift into the evening the way a
  # 24 hour interval measured from the last change does.
  television.assign_attributes(cycle_seconds: 1.day.to_i, rotate_at: "03:00",
                               follows_display: nil)
end
television.update!(
  name: "Television", width: 3840, height: 2160,
  # Crops, and its aspect window is what decides the whole collection, because
  # the kiosk may only pick what this screen can also render. 0.20 is at most a
  # fifth of the picture discarded, so 10% off each edge.
  #
  # It was 0.10 for a few hours. 0.20 was rejected earlier on the strength of a
  # MATTE at that tolerance, which is a different judgement: a fifth of the panel
  # given over to mount board looks like a small picture adrift, where a fifth
  # cropped off a large painting reads as a tighter frame. Judged on The Potato
  # Eaters at 1.414, the worst case this window admits.
  #
  # This is the single most valuable number in the app. Widening it from 0.10
  # returned 26 famous paintings already in the collection -- Nighthawks,
  # Primavera, Ophelia, the Grande Jatte -- and four Group of Seven works, at no
  # cost but a warm pass. See docs/adr/20260817-fit-the-screen-not-the-art.md.
  # Raised to 0.254 on 2026-08-18, and the odd third decimal is the whole point:
  # it is high enough for the worst crop Mike approved (The Anatomy Lesson at
  # 25.33%) and low enough to keep out the next one he did not (The Old Musician
  # at 25.64%). A 0.23 point gap. He reviewed all 36 candidates as pairs — whole
  # picture beside the frame the television would show — and kept 31.
  #
  # The five refusals are not a band, they are scattered through the range, which
  # is the finding: 29.7% ruins Liberty Leading the People while 30.9% leaves The
  # Night Watch intact, because what matters is whether the discarded strips carry
  # any of the composition. So the number cannot be raised further on argument
  # alone. Two refusals fall below this figure and are held off the television by
  # display_overrides; the other three are simply above it. Seven kept pieces are
  # above it too and carry their own Artwork#max_crop_fraction.
  #
  # CHANGING THIS NUMBER HERE RE-SEEDS IT ONTO THE LIVE DISPLAY. It reached 0.20
  # the same way and a re-seed would have quietly undone the review.
  render_mode: "fill", max_crop_fraction: 0.254,
  # http, not file. This was a file drop for one day, because the uploader was a
  # cron script that had to read the rendition from somewhere. The upload now
  # lives in a Home Assistant integration, which fetches current.json and then
  # the rendition URL like any other client — so there is no shared filesystem,
  # no rename() dance, and both screens are ordinary subscribers to one feed.
  # `file` delivery is still supported; nothing here uses it.
  delivery: "http", file_path: nil, active: true
)

# Both screens carry everything. What actually reaches a screen is decided by
# whether the picture suits that panel — computed, per display — and not by
# curation lists pulling in two directions.
#
# Each screen now chooses for itself, so each gets the whole set it can render
# rather than the intersection the follow arrangement forced. The kiosk clears 276
# of 289 on its own where the shared set was 214, and those 62 extra pieces are
# ones the 4K panel is simply too large for.

# How often a collection comes up, per screen. This is the ONLY weight that acts
# on a collection: Display#weight_for multiplies an artwork's own weight by the
# one on this join, and nothing reads a weight from the collection itself.
#
# Cartoons at 2 gives them about 13% of a round, one showing in seven or eight,
# which is the cadence they had before a hundred paintings arrived and diluted
# them to one in nineteen. It was 1 for a day, correctly: only two cartoons were
# large enough for the 4K panel then, and boosting a collection of two does not
# add variety, it just shows the same two pictures more often. Nine of them now
# clear the panel, so the reason expired.
#
# **The count is what governs this.** Revisit the number when the number of
# active cartoons changes materially, not on taste.
COLLECTION_WEIGHTS = { "Cartoons" => 2 }.freeze

[ kiosk, television ].each do |display|
  collections.each do |name, collection|
    pairing = DisplayCollection.find_or_initialize_by(display: display, collection: collection)
    # Set on both screens, and consulted on both: each one picks its own artwork
    # now, so each one weighs the collections itself.
    pairing.update!(weight: COLLECTION_WEIGHTS.fetch(name, 1))
  end
end

puts "seeded #{Collection.count} collections and #{Display.count} displays"
