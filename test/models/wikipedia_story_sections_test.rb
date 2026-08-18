require "test_helper"

# The plain-text extract is a lead followed by "== Heading ==" sections. Splitting
# them needs a newline on both sides of a heading, and an article ending in
# "== References ==" has none after it — so the heading survived into the lead and
# reached the wall as literal markup on four stories.
class WikipediaStorySectionsTest < ActiveSupport::TestCase
  def build(text)
    WikipediaStory.new("Some Painting").send(:build, text)
  end

  test "a trailing section heading does not survive into the story" do
    story = build("A painting of a thing. It hangs somewhere.\n\n== References ==")

    assert_not_includes story, "==", "wiki markup reached the wall four times"
    assert_equal "A painting of a thing. It hangs somewhere.", story
  end

  test "a trailing heading with a stub body is dropped too" do
    story = build("A painting.\n\n== References ==\n\nCited in a list.")

    assert_not_includes story, "References"
  end

  test "a heading in the middle is still handled" do
    story = build("The lead.\n\n== Reception ==\n\n#{'Critics liked it. ' * 12}")

    assert story.start_with?("The lead.")
    assert_not_includes story, "=="
  end
end
