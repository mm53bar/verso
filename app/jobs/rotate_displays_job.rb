# The clock for every screen verso drives.
#
# One job over one table, so a browser polling HTTP and a script reading a file
# are the same code path with different last steps — see
# docs/adr/20260816-verso-owns-the-rotation.md. Adding a third screen is a row.
class RotateDisplaysJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    advanced = []

    Display.active.find_each do |display|
      next unless display.due?(now: now)

      artwork = display.advance!(now: now)

      if artwork.nil?
        # Nothing eligible. Leave the screen showing whatever it has rather than
        # blanking it, and say so — an empty result usually means a filter is
        # wrong, not that the collection is empty.
        Rails.logger.warn("[verso] #{display.slug}: nothing eligible to show")
        next
      end

      display.deliver!
      advanced << display.slug
      Rails.logger.info("[verso] #{display.slug}: now showing #{artwork.slug}")
    end

    advanced
  end
end
