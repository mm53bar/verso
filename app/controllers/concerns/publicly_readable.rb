# Marks a controller's responses as readable by script on any origin.
#
# The kiosk that consumes the feed shows a dashboard served from a loopback
# origin on the device itself, so its fetch is cross-origin, and Rails sends no
# CORS header by default. The failure is silent: the fetch rejects, the screen
# keeps whatever wallpaper it had, and nothing looks broken.
#
# Deliberately not applied application-wide. The ingestion path has no CORS
# header, so a JSON POST from another origin fails its preflight and a page on
# the internet cannot drive an app that has no authentication — see
# docs/adr/20260816-cors-on-the-feed-routes.md.
module PubliclyReadable
  extend ActiveSupport::Concern

  included do
    before_action :allow_cross_origin_reads
  end

  private
    def allow_cross_origin_reads
      response.set_header("Access-Control-Allow-Origin", "*")
    end
end
