require "open-uri"
require "json"

# Builds an artwork's story from its own Wikipedia article.
#
# The story is about the *picture*, not the painter. An artist's biography is
# the same paragraph on fifteen Tom Thomson panels, and it does not tell you
# anything about the one you are looking at. So the lead of the artwork's own
# article comes first, and then — where the article has one — a section of
# critical assessment, which is the closest thing to "what do people make of
# this" that exists in a citable form.
#
# Nothing here is written by verso. Wikipedia prose is CC BY-SA, so every story
# records where it came from and the pages that show it link back.
class WikipediaStory
  API = "https://en.wikipedia.org/w/api.php".freeze
  USER_AGENT = ArtworkImporter::USER_AGENT

  # One article per request, deliberately. `prop=extracts` caps exlimit at 1
  # whenever exintro is not set, so a multi-title request for FULL text returns
  # the first page and silently empty extracts for the rest — a quiet failure
  # that looks like missing articles. Only intro-only extracts can be batched,
  # and the intro is precisely what does not contain the critical assessment.
  PACE = 0.4

  # Sections that assess the work rather than narrate its provenance. Ordered by
  # preference: an explicit analysis beats a reception summary, which beats a
  # bare description.
  ASSESSMENT = [
    /\A(composition and )?analysis\b/i,
    /\Ainterpretation/i,
    /\A(critical )?reception\b/i,
    /\Acriticism\b/i,
    /\Alegacy\b/i,
    /\Ainfluence\b/i,
    /\Astyle\b/i,
    /\Asubject\b/i,
    /\Adescription\b/i
  ].freeze

  LEAD_LIMIT = 900
  ASSESSMENT_LIMIT = 1100

  # Below this a "story" is a stub or a disambiguation page, and showing it is
  # worse than showing nothing — it looks like the feature is broken rather than
  # like the encyclopaedia is thin on this piece.
  MINIMUM = 250

  Story = Struct.new(:title, :text, :url, keyword_init: true)

  # titles: Wikipedia page titles. Returns { title => Story }.
  def self.for(titles, sleeper: method(:sleep))
    Array(titles).compact.uniq.each_with_object({}).with_index do |(title, stories), index|
      sleeper.call(PACE) if index.positive?
      stories.merge!(new(title).call)
    end
  end

  def initialize(title)
    @title = title
  end

  def call
    pages.each_with_object({}) do |page, stories|
      text = page["extract"].to_s
      next if text.blank?

      story = build(text)
      next if story.length < MINIMUM

      stories[page["title"]] = Story.new(
        title: page["title"], text: story,
        url: "https://en.wikipedia.org/wiki/#{ERB::Util.url_encode(page['title'].tr(' ', '_'))}"
      )
    end
  end

  private
    def pages
      params = {
        action: "query", format: "json", prop: "extracts", explaintext: 1,
        redirects: 1, titles: @title
      }
      body = URI.open("#{API}?#{params.to_query}", "User-Agent" => USER_AGENT, read_timeout: 60).read

      JSON.parse(body).dig("query", "pages").to_h.values
    rescue StandardError => e
      Rails.logger.warn("[verso] wikipedia fetch failed: #{e.class}: #{e.message}")
      []
    end

    # The plain-text extract uses "== Heading ==" lines, so the article splits
    # into a lead followed by (heading, body) pairs.
    def build(text)
      parts = ("\n" + text).split(/\n==+ ([^=]+?) ==+\n/)
      lead = trim(parts.first.to_s.strip, LEAD_LIMIT)
      sections = parts.drop(1).each_slice(2).to_a.select { |pair| pair.length == 2 }
                      .map { |heading, body| [ heading.strip, body.strip ] }

      [ lead, assessment(sections) ].compact_blank.join("\n\n")
    end

    def assessment(sections)
      ASSESSMENT.each do |pattern|
        found = sections.find { |heading, body| heading.match?(pattern) && body.length > 120 }
        return trim(readable(found.last), ASSESSMENT_LIMIT) if found
      end

      nil
    end

    # Stop before a quotation. The plain-text extract flattens blockquotes into
    # ordinary paragraphs, so an article that says "...Vincent remarks:" followed
    # by a letter yields a paragraph starting mid-thought, with no indication it
    # is a quote. On a wall that reads as a bug rather than as an excerpt.
    def readable(body)
      kept = []
      body.split(/\n+/).each do |paragraph|
        # A paragraph ending in a colon introduces the quote that follows, so
        # keeping it leaves a sentence dangling into nothing.
        break if paragraph.strip.end_with?(":")

        kept << paragraph
      end

      kept.join("\n\n").strip
    end

    # Cut at a sentence boundary rather than mid-word; a story that stops in the
    # middle of a clause reads as broken rather than abridged.
    def trim(text, limit)
      return text if text.length <= limit

      cut = text[0, limit]
      boundary = cut.rindex(/\.\s/) || cut.rindex(" ")

      "#{cut[0, (boundary || limit) + 1].strip}…"
    end
end
