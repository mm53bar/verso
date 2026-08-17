require "open-uri"
require "json"

# Looks up what is actually known about an artwork, so verso does not have to
# invent it.
#
# This matters more than it looks. The point of the app is metadata you can
# trust: a caption on a kitchen wall saying a painting hangs in the Met is worse
# than no caption at all, because nobody will check it. So facts come from a
# source with a citation — Wikidata for structured claims, Wikipedia for prose —
# and never from a guess.
#
# Wikidata knows, per artwork:
#
#   P195  collection   the museum or body that owns it
#   P276  location     where it physically is, occasionally down to the room
#   P571  inception    when it was made
#   P186  material     oil on canvas, tempera on panel
#   P135  movement     Impressionism, Group of Seven
#
# Queried in batches through SPARQL rather than one request per artwork: the
# endpoint is rate-limited and 150 individual queries is rude.
class WikidataLookup
  ENDPOINT = "https://query.wikidata.org/sparql".freeze
  SUMMARY = "https://en.wikipedia.org/api/rest_v1/page/summary/".freeze
  USER_AGENT = ArtworkImporter::USER_AGENT
  BATCH = 50

  Facts = Struct.new(:qid, :title, :collection, :location, :inception, :materials,
                     :movement, :article, keyword_init: true) do
    # A room, gallery, floor or wing — something *inside* an institution.
    WITHIN_A_BUILDING = /\b(room|sala|salle|saal|gallery \d|floor|wing)\b/i

    # What to show as "where it hangs".
    #
    # The collection (P195) is who owns it, and is what a person would say:
    # "the National Gallery". The location (P276) is riskier than it looks —
    # Wikidata records *former* homes there too, so trusting it blindly produced
    # "Musée d'Orsay — Luxembourg Museum" for the Renoir and put Primavera in
    # the bedroom it left five centuries ago. On a wall caption nobody will
    # check, a confidently wrong fact is worse than a missing one.
    #
    # So the location is appended only when it clearly names somewhere inside a
    # building, which is exactly the case worth having: "room 44".
    def housed_at
      return location if collection.blank?
      return collection if location.blank? || location == collection
      return collection unless location.match?(WITHIN_A_BUILDING)
      return collection if collection.include?(location) || location.include?(collection)

      "#{collection} — #{location}"
    end

    # Wikidata records the support and the paint as separate claims, so a work
    # comes back as "oil paint" plus "canvas". Neither alone is a medium.
    def medium
      parts = Array(materials).map(&:strip).reject(&:blank?).uniq
      return if parts.empty?

      paints, supports = parts.partition { |p| p.match?(/paint|tempera|ink|watercolou?r|gouache|pastel/i) }
      return parts.to_sentence if paints.empty? || supports.empty?

      "#{paints.to_sentence} on #{supports.to_sentence}"
    end

    def year
      inception.to_s[/\A-?\d{1,4}/]
    end
  end

  def self.facts_for(qids)
    qids = Array(qids).compact.uniq
    return {} if qids.empty?

    qids.each_slice(BATCH).reduce({}) { |all, slice| all.merge(new(slice).call) }
  end

  def initialize(qids)
    @qids = Array(qids)
  end

  def call
    rows = query
    return {} if rows.nil?

    rows.each_with_object({}) do |row, facts|
      qid = row.dig("item", "value").to_s.split("/").last
      next if qid.blank?

      facts[qid] ||= Facts.new(qid: qid, materials: [])
      record = facts[qid]
      record.title      ||= value(row, "itemLabel")
      record.collection ||= value(row, "collectionLabel")
      record.location   ||= value(row, "locationLabel")
      record.inception  ||= value(row, "inception")
      # One row per material claim, so collect rather than overwrite. They
      # cannot be GROUP_CONCAT-ed in SPARQL: the label service runs after the
      # query, so an auto-generated ?xLabel is not bound at aggregation time.
      material = value(row, "materialLabel")
      record.materials << material if material && record.materials.exclude?(material)
      record.movement   ||= value(row, "movementLabel")
      record.article    ||= value(row, "article")
    end
  end

  private
    # A lookup that failed, dressed as an answer. The label service has two ways
    # of doing this and both have reached the screens:
    #
    #   * an anonymous node comes back as its raw URI,
    #     "http://www.wikidata.org/.well-known/genid/9be35fb1…"
    #   * an entity with no label in any requested language comes back as its
    #     bare id, "Q214867" — which is the National Gallery of Art in
    #     Washington, and which sat in `current_location` on nine artworks and
    #     was corrected by hand three times before being fixed here.
    #
    # Neither is a name, and a blurb is read aloud, so neither can be stored.
    UNLABELLED = /\A(?:https?:\/\/|Q\d+\z)/

    def value(row, key)
      raw = row.dig(key, "value").presence
      return raw if key == "article"
      return if raw.nil? || raw.match?(UNLABELLED)

      raw
    end

    def query
      url = "#{ENDPOINT}?#{{ query: sparql, format: 'json' }.to_query}"
      body = URI.open(url, "User-Agent" => USER_AGENT, read_timeout: 60).read

      JSON.parse(body).dig("results", "bindings")
    rescue StandardError => e
      Rails.logger.warn("[verso] wikidata lookup failed: #{e.class}: #{e.message}")
      nil
    end

    def sparql
      values = @qids.map { |qid| "wd:#{qid}" }.join(" ")

      <<~SPARQL
        SELECT ?item ?itemLabel ?collectionLabel ?locationLabel ?inception
               ?materialLabel ?movementLabel ?article WHERE {
          VALUES ?item { #{values} }
          OPTIONAL { ?item wdt:P195 ?collection. }
          OPTIONAL { ?item wdt:P276 ?location. }
          OPTIONAL { ?item wdt:P571 ?inception. }
          OPTIONAL { ?item wdt:P186 ?material. }
          OPTIONAL { ?item wdt:P135 ?movement. }
          OPTIONAL {
            ?article schema:about ?item ;
                     schema:isPartOf <https://en.wikipedia.org/> .
          }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }

      SPARQL
    end
end
