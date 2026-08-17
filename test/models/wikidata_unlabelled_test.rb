require "test_helper"

# Wikidata's label service answers a failed lookup with something that looks like
# an answer, and both of its ways of doing that have reached the screens: an
# anonymous node as a raw URI, and an unlabelled entity as its bare id. A blurb is
# read aloud, so "Q214867" cannot be an artwork's location.
class WikidataUnlabelledTest < ActiveSupport::TestCase
  def value_for(raw, key: "where")
    WikidataLookup.new([]).send(:value, { key => { "value" => raw } }, key)
  end

  test "a bare entity id is not a name" do
    assert_nil value_for("Q214867"),
      "this is the National Gallery of Art, and it reached current_location nine times"
    assert_nil value_for("Q1117704")
  end

  test "an anonymous node is not a name" do
    assert_nil value_for("http://www.wikidata.org/.well-known/genid/20dde0ce1d")
  end

  test "a real label passes through" do
    assert_equal "Rijksmuseum", value_for("Rijksmuseum")
    assert_equal "Musée du Louvre", value_for("Musée du Louvre")
  end

  test "something that merely starts with Q is fine" do
    assert_equal "Quai d'Orsay", value_for("Quai d'Orsay"),
      "the guard is for bare ids, not for words beginning with Q"
  end

  test "an article url is still a url, because that one is meant to be" do
    url = "https://en.wikipedia.org/wiki/The_Night_Watch"

    assert_equal url, value_for(url, key: "article")
  end
end
