class AddMaxCropFractionToArtworks < ActiveRecord::Migration[8.1]
  # How much of ITSELF this picture is worth losing, when that is more than the
  # screen would ordinarily take.
  #
  # The television accepts a 20% crop, which is a judgement about pictures in
  # general and refuses two that Mike wants anyway: The Night Watch needs 31% and
  # The Starry Night 29%. Raising the television's own figure to 31% would let them
  # in and would also admit about thirty six other artworks whose crops nobody has
  # looked at. That is the wrong trade — the decision here is about two paintings,
  # not about a policy.
  #
  # NOT AN ELIGIBILITY FLAG. `display_overrides` already exists for per-artwork
  # exceptions and would have been fewer lines, but it says "show this regardless"
  # and suitability in this app is computed, never flagged. A tolerance keeps it
  # computed: the same arithmetic runs, with a number this artwork supplies instead
  # of the one the panel supplies. It also records how much crop was actually
  # accepted, which a boolean would throw away.
  #
  # Null means "use the screen's figure", which is every artwork but a handful.
  def change
    add_column :artworks, :max_crop_fraction, :decimal, precision: 3, scale: 2
  end
end
