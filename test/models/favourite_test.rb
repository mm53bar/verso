require "test_helper"

# A star does exactly one thing: the piece comes up twice as often. It is a
# boolean rather than a second weight column, because we already deleted one of
# those — Collection#weight sat unread for a day, and two weights that have to be
# multiplied make the frequency something you work out rather than read.
class FavouriteTest < ActiveSupport::TestCase
  setup do
    @kiosk = displays(:kiosk)
    @artwork = artworks(:native_4k)
  end

  test "starring doubles the weight the rotation gives it" do
    before = @kiosk.weight_for(@artwork)

    @artwork.update!(favourite: true)

    assert_equal before * Display::FAVOURITE_MULTIPLIER, @kiosk.weight_for(@artwork.reload)
  end

  test "the star multiplies, so it stacks with the collection's own weight" do
    pairing = @kiosk.display_collections.find_by(collection: @artwork.collection)
    pairing.update!(weight: 3)
    @artwork.update!(favourite: true, weight: 1)

    assert_equal 6, @kiosk.weight_for(@artwork.reload),
      "3 for the collection on this screen, doubled for the star"
  end

  test "nothing is starred by default" do
    assert_not_predicate Artwork.new, :favourite?
    assert_empty Artwork.starred
  end

  test "a star gives a piece more slots in a round" do
    @artwork.update!(favourite: true)

    slots = @kiosk.send(:remaining_slots)

    assert_equal @kiosk.weight_for(@artwork), slots[@artwork],
      "the extra weight has to arrive as extra slots or the star does nothing"
  end
end
