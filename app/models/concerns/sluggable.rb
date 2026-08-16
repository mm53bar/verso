# Gives a model a URL-safe slug derived from whatever it calls itself.
#
# Slugs are assigned once and then left alone: they appear in feed URLs that
# clients cache, so regenerating one when a title is corrected would look to a
# screen like a different artwork.
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :assign_slug, on: :create
    validates :slug, presence: true, uniqueness: true
  end

  private
    # Overridden by models whose natural name lives somewhere other than #name.
    def slug_source
      name
    end

    def assign_slug
      return if slug.present?

      base = slug_source.to_s.parameterize
      base = "untitled" if base.blank?

      self.slug = base
      suffix = 2
      while self.class.exists?(slug: self.slug)
        self.slug = "#{base}-#{suffix}"
        suffix += 1
      end
    end
end
