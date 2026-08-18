class AddCropFocusToArtworks < ActiveRecord::Migration[8.1]
  # Where to keep when a picture has to lose some of itself.
  #
  # Cropping to fill discards from ONE axis only — whichever the artwork has too
  # much of relative to the panel — and until now it always discarded evenly from
  # both ends of it. That is the right default and the wrong answer for a
  # particular painting: The Night Watch is 1.23 against the television's 1.78, so
  # 31% of its height goes, and a centred crop takes half of that off the floor,
  # where the feet and the foreground are, to save an equal amount of the dark
  # arch above the figures that carries almost nothing.
  #
  # TWO COLUMNS, NOT ONE, and the reason is that libvips takes a single value.
  # Its `crop:` option means "keep the low edge" or "keep the high edge" of
  # whatever axis is being cropped, so one stored value cannot say both "keep the
  # floor" and "keep the left" — and this collection needs both, because the same
  # artwork is cropped vertically for the 16:9 television and horizontally for the
  # 16:10 kiosk. Exactly one axis is ever cropped for a given pair, so storing a
  # preference per axis is unambiguous: pick the one belonging to the axis that
  # actually loses pixels.
  #
  # Defaults are NULL rather than "centre" on purpose. An explicit centre would
  # have to be passed to libvips as `crop: :centre`, which changes the
  # transformation hash, which changes every variant key, which would regenerate
  # all 570-odd renditions in the collection to produce identical images.
  def change
    add_column :artworks, :crop_focus_x, :string
    add_column :artworks, :crop_focus_y, :string
  end
end
