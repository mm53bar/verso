require "test_helper"

class WikimediaCommonsTest < ActiveSupport::TestCase
  # Verified against the live service on 2026-08-16: this exact URL returns 200.
  MANET = "Un bar aux Folies-Bergère d'E. Manet (Fondation Vuitton, Paris) (33539037428).jpg"

  test "shards the path by the md5 of the underscored filename" do
    # "Foo.jpg" -> md5 is 0ce1585... so the shard is 0/0c
    url = WikimediaCommons.new("Foo.jpg").original_url

    assert_equal "#{WikimediaCommons::BASE}/#{Digest::MD5.hexdigest('Foo.jpg')[0]}/" \
                 "#{Digest::MD5.hexdigest('Foo.jpg')[0, 2]}/Foo.jpg", url
  end

  test "spaces become underscores before hashing, as Commons does" do
    spaced = WikimediaCommons.new("The Jack Pine.jpg").original_url
    scored = WikimediaCommons.new("The_Jack_Pine.jpg").original_url

    assert_equal scored, spaced
  end

  test "accents, apostrophes and parentheses are percent-encoded" do
    url = WikimediaCommons.new(MANET).original_url

    assert_includes url, "Folies-Berg%C3%A8re"
    assert_includes url, "d%27E."
    assert_includes url, "%2833539037428%29"
    assert_not_includes url, " "
  end

  test "a thumbnail repeats the escaped name in the final segment" do
    url = WikimediaCommons.new("The Jack Pine.jpg").thumbnail_url(3840)

    assert_includes url, "/thumb/"
    assert url.end_with?("/3840px-The_Jack_Pine.jpg")
  end

  test "a width Commons will not render is refused here rather than at the server" do
    error = assert_raises(WikimediaCommons::UnsupportedWidth) do
      WikimediaCommons.new("The Jack Pine.jpg").thumbnail_url(2560)
    end

    assert_match(/3840/, error.message)
  end

  test "every supported width is accepted" do
    commons = WikimediaCommons.new("The Jack Pine.jpg")

    WikimediaCommons::THUMBNAIL_WIDTHS.each do |width|
      assert_includes commons.thumbnail_url(width), "/#{width}px-"
    end
  end

  test "the page url points at the description page, not the bytes" do
    assert_includes WikimediaCommons.new("The Jack Pine.jpg").page_url,
                    "commons.wikimedia.org/wiki/File:"
  end
end
