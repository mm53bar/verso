json.display @display.slug
json.cycle_seconds @display.cycle_seconds
json.seconds_remaining @seconds_remaining

if @artwork
  json.artwork_id @artwork.id
  json.slug @artwork.slug
  json.url artwork_rendition_url(@artwork.slug, @display.slug, format: :jpg)
  json.since @display.current_since&.iso8601

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
end

json.next_url(@next_artwork ? artwork_rendition_url(@next_artwork.slug, @display.slug, format: :jpg) : nil)
