# Pre-generates every derived image, so no screen and no browser ever waits on
# libvips.
#
# Deriving on demand is fine on a workstation and not fine on the NAS: measured
# there, a 480x300 thumbnail from a 717MB original takes 42 seconds, and Puma
# has three threads. A browser opening the collection index could therefore
# occupy every thread for minutes and starve the kiosk's feed.
class WarmDerivativesJob < ApplicationJob
  queue_as :default

  def perform(artwork_id = nil)
    scope = artwork_id ? Artwork.where(id: artwork_id) : Artwork.all
    warmed = 0

    scope.find_each do |artwork|
      warmed += artwork.warm_derivatives!
    rescue StandardError => e
      Rails.logger.warn("[verso] warm #{artwork.slug}: #{e.class}: #{e.message}")
    end

    Rails.logger.info("[verso] warmed #{warmed} derivatives")
    warmed
  end
end
