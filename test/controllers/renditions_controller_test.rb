require "test_helper"

class RenditionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @artwork = artworks(:native_4k)
    @artwork.original.attach(
      io: file_fixture("wide.jpg").open, filename: "wide.jpg", content_type: "image/jpeg"
    )
    @kiosk = displays(:kiosk)
  end

  test "serves the artwork cropped to fill the display" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug)

    assert_response :success
    assert_equal "image/jpeg", response.media_type

    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal @kiosk.width, image.width
    assert_equal @kiosk.height, image.height
  end

  test "the same artwork is cropped differently for a different display" do
    get artwork_rendition_url(@artwork.slug, displays(:television).slug)

    image = Vips::Image.new_from_buffer(response.body, "")

    assert_equal 3840, image.width
    assert_equal 2160, image.height
  end

  test "streams the bytes rather than redirecting" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug)

    assert_response :success
    assert_not response.redirect?,
      "a redirect costs a second round trip at the moment a screen is swapping"
  end

  test "is cacheable forever, because the url names one artwork at one size" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug)

    assert_includes response.headers["Cache-Control"], "immutable"
    assert_includes response.headers["Cache-Control"], "public"
  end

  # The integration harness computes a Content-Length whether the controller
  # supplied one or not, so no request-level assertion can tell a buffered
  # response from a streamed one — the streamed version passed these same tests
  # while production served chunked responses with no length and answered every
  # HEAD with 0. This is the assertion that actually holds the fix in place.
  test "does not stream, because a streamed response cannot carry a length" do
    assert_not RenditionsController.include?(ActionController::Live),
      "ActiveStorage::Streaming pulls in Live, whose Buffer deletes " \
      "Content-Length on the first write"
  end

  test "says how many bytes it is sending" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug)

    assert_response :success
    assert_equal response.body.bytesize.to_s, response.headers["Content-Length"],
      "a streamed response defaults to no Content-Length at all"
  end

  test "a HEAD answers with the real length, without reading the bytes" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug)
    length = response.headers["Content-Length"]

    head artwork_rendition_url(@artwork.slug, @kiosk.slug)

    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal length, response.headers["Content-Length"],
      "a HEAD that reports 0 bytes for a real image is a wrong answer, not a missing one"
    assert_predicate response.body, :empty?
  end

  test "the url carries the extension of the format it is served in" do
    url = artwork_rendition_url(@artwork.slug, @kiosk.slug,
                                format: @kiosk.rendition_extension)

    assert url.end_with?(".jpg"),
      "clients are meant to be dumb, so the url says what it is: #{url}"

    get url

    assert_response :success
    assert_equal "image/jpeg", response.media_type
  end

  test "still serves an extensionless url, so old clients keep working" do
    get "/artworks/#{@artwork.slug}/renditions/#{@kiosk.slug}"

    assert_response :success
    assert_equal "image/jpeg", response.media_type
  end

  test "an artwork with no bytes is a 404 rather than an error" do
    get artwork_rendition_url(artworks(:cartoon).slug, @kiosk.slug)

    assert_response :not_found
  end

  test "unknown artwork or display is a 404" do
    get artwork_rendition_url("no-such-artwork", @kiosk.slug)
    assert_response :not_found

    get artwork_rendition_url(@artwork.slug, "no-such-display")
    assert_response :not_found
  end

  test "serves a named size for the browse UI" do
    get artwork_variant_url(@artwork.slug, :thumb, format: :jpg)

    assert_response :success
    assert_equal "image/jpeg", response.media_type

    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal 480, image.width
    assert_equal 300, image.height
  end

  test "each named size is a different size" do
    get artwork_variant_url(@artwork.slug, :tile, format: :jpg)

    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal 160, image.width
    assert_equal 100, image.height
  end

  test "a named size url carries the extension, like a rendition url" do
    url = artwork_variant_url(@artwork.slug, :thumb, format: :jpg)

    assert url.end_with?(".jpg"), "the url should say what it is: #{url}"
  end

  test "a size nobody declared is a 404, not an arbitrary transformation" do
    get "/artworks/#{@artwork.slug}/variants/4000x4000.jpg"

    assert_response :not_found,
      "an open transformation parameter on a 717MB original is a denial of service"
  end

  test "a HEAD for a named size answers with the real length" do
    get artwork_variant_url(@artwork.slug, :thumb, format: :jpg)
    length = response.headers["Content-Length"]

    head artwork_variant_url(@artwork.slug, :thumb, format: :jpg)

    assert_response :success
    assert_equal length, response.headers["Content-Length"]
    assert_predicate response.body, :empty?
  end

  test "an artwork with no bytes is a 404 for a named size too" do
    get artwork_variant_url(artworks(:cartoon).slug, :thumb, format: :jpg)

    assert_response :not_found
  end

  # THE ASSERTION THAT HOLDS THE ACCELERATION IN PLACE.
  # Rack::Sendfile only rewrites a response whose body responds to `to_path`,
  # which is true of `send_file` and false of `send_data` and of anything
  # streamed. It normally reads the variation from
  # config.action_dispatch.x_sendfile_header, which is production-only and is
  # baked into the middleware at boot -- but it also honours `sendfile.type` in
  # the Rack env, so a single request can ask for the same treatment here. If
  # this controller ever goes back to buffering, the header does not appear.
  %i[ thumb tile detail ].each do |size|
    test "hands the proxy a path rather than the bytes for #{size}" do
      get artwork_variant_url(@artwork.slug, size, format: :jpg),
        headers: { "sendfile.type" => "X-Sendfile" }

      assert_response :success
      path = response.headers["x-sendfile"] || response.headers["X-Sendfile"]

      assert path.present?,
        "no X-Sendfile header: the body did not respond to to_path, so Ruby is " \
        "carrying every byte and Thruster cannot serve the file itself"
      assert_predicate File.size(path), :positive?
    end
  end

  test "a rendition hands the proxy a path too" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug),
      headers: { "sendfile.type" => "X-Sendfile" }

    assert_response :success
    assert (response.headers["x-sendfile"] || response.headers["X-Sendfile"]).present?
  end

  # The `v` param is a cache buster and nothing else. It must not become a
  # condition of service: a kiosk page rendered an hour ago carries whatever
  # fingerprint was current then, and it should still get an image rather than a
  # 404 the moment a crop changes.
  test "an old or absent fingerprint still serves the current bytes" do
    current = get_bytes artwork_rendition_url(@artwork.slug, @kiosk.slug,
                                              format: :jpg,
                                              v: @artwork.rendition_fingerprint(@kiosk))
    stale = get_bytes artwork_rendition_url(@artwork.slug, @kiosk.slug,
                                            format: :jpg, v: "deadbeef")
    bare = get_bytes artwork_rendition_url(@artwork.slug, @kiosk.slug, format: :jpg)

    assert_equal current, stale
    assert_equal current, bare
  end

  private
    def get_bytes(url)
      get url

      assert_response :success
      response.body.bytesize
    end
end
