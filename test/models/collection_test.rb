require "test_helper"

class CollectionTest < ActiveSupport::TestCase
  test "slug comes from the name" do
    assert_equal "samsung-frame-collection", Collection.create!(name: "Samsung Frame collection").slug
  end

  test "a collection holding artworks refuses to be deleted" do
    canon = collections(:canon)

    assert_no_difference -> { Artwork.count } do
      assert_not canon.destroy
    end

    assert_predicate canon.errors[:base], :any?
  end

  test "an empty collection can be deleted" do
    assert Collection.create!(name: "Scratch").destroy
  end

  test "the aspect floor is optional and must be positive when set" do
    assert_predicate Collection.new(name: "No floor"), :valid?
    assert_not Collection.new(name: "Bad floor", minimum_aspect_ratio: 0).valid?
  end

  test "weight must be positive" do
    assert_not Collection.new(name: "Zero", weight: 0).valid?
  end
end
