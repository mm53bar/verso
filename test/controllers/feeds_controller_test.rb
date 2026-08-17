require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kiosk = displays(:kiosk)
    @artwork = artworks(:sketch_panel)
    @artwork.original.attach(
      io: file_fixture("landscape.jpg").open, filename: "landscape.jpg", content_type: "image/jpeg"
    )
    @kiosk.update!(current_artwork: @artwork, next_artwork: artworks(:native_4k),
                   current_since: Time.current)
  end

  test "reports what is showing, with the metadata a caption needs" do
    get display_current_url(@kiosk.slug)

    assert_response :success
    body = response.parsed_body

    assert_equal @artwork.id, body["artwork_id"]
    assert_equal "A sketch panel", body["title"]
    assert_equal "Tom Thomson", body["artist"]
    assert_equal "Canadian", body["collection"]
    assert_equal 1800, body["cycle_seconds"]
  end

  test "the image url is addressed by artwork and display, not by storage key" do
    get display_current_url(@kiosk.slug)
    url = response.parsed_body["url"]

    assert_includes url, "/artworks/#{@artwork.slug}/renditions/#{@kiosk.slug}"
    assert_not_includes url, "blob"
  end

  test "reports what to preload next" do
    get display_current_url(@kiosk.slug)

    assert_includes response.parsed_body["next_url"], artworks(:native_4k).slug
  end

  test "the urls it publishes say what format they are" do
    get display_current_url(@kiosk.slug)

    # A client should not have to read a Content-Type -- or worse, the bytes --
    # to learn that an image is a JPEG. One of them refused it outright instead.
    assert response.parsed_body["url"].end_with?(".jpg"),
      "feed url gives no clue what it serves: #{response.parsed_body["url"]}"
    assert response.parsed_body["next_url"].end_with?(".jpg"),
      "next_url gives no clue what it serves: #{response.parsed_body["next_url"]}"
  end

  test "reports how long the current piece has left, so a client can poll freely" do
    @kiosk.update!(current_since: 300.seconds.ago)

    get display_current_url(@kiosk.slug)

    assert_in_delta 1500, response.parsed_body["seconds_remaining"], 5
  end

  test "seconds remaining never goes negative when the job is late" do
    @kiosk.update!(current_since: 10.hours.ago)

    get display_current_url(@kiosk.slug)

    assert_equal 0, response.parsed_body["seconds_remaining"]
  end

  test "script on any origin may read the feed" do
    get display_current_url(@kiosk.slug)

    assert_equal "*", response.headers["Access-Control-Allow-Origin"],
      "without this the kiosk fetch fails silently and the screen just never changes"
  end

  test "a display showing nothing yet answers rather than erroring" do
    @kiosk.update!(current_artwork: nil, next_artwork: nil, current_since: nil)

    get display_current_url(@kiosk.slug)

    assert_response :success
    assert_nil response.parsed_body["artwork_id"]
    assert_nil response.parsed_body["url"]
  end

  test "an unknown display is a 404, not a 500" do
    get display_current_url("no-such-screen")

    assert_response :not_found
  end

  test "an unchanged feed can be answered from cache" do
    get display_current_url(@kiosk.slug)
    etag = response.headers["ETag"]

    assert_not_nil etag

    get display_current_url(@kiosk.slug), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end
end
