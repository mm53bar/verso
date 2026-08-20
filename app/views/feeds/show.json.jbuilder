json.display @display.slug
json.cycle_seconds @display.cadence_seconds
json.seconds_remaining @seconds_remaining

if @artwork
  json.artwork_id @artwork.id
  json.slug @artwork.slug
  json.url artwork_rendition_url_for(@artwork, @display)
  json.since @display.current_since&.iso8601

  # WHAT THE BYTES ARE, as opposed to which artwork they depict. A consumer that
  # remembers what it last delivered must key on this and not on artwork_id.
  #
  # They used to be the same question. A rendition was a function of (artwork,
  # display) until Artwork#crop_edge_for made it a function of (artwork, display,
  # crop focus), and the difference cost twenty minutes of a television showing an
  # old crop of the right painting: Home Assistant skips an upload when the artwork
  # id matches what it last sent, and it did match. This is the value it should
  # have been comparing, and it is also the `v` in the url above.
  json.rendition_version @artwork.rendition_fingerprint(@display)

  json.title @artwork.title
  json.artist @artwork.artist&.name
  json.year @artwork.year_text
  json.collection @artwork.collection.name
  json.credit @artwork.credit_line
  json.location @artwork.current_location

  # Two story fields, deliberately: blurb is what gets spoken, story is what
  # gets read. See docs/adr/ and the Artwork model.
  json.blurb @artwork.blurb
else
  json.artwork_id nil
  json.url nil
  json.rendition_version nil
end

json.next_url(@next_artwork ? artwork_rendition_url_for(@next_artwork, @display) : nil)
