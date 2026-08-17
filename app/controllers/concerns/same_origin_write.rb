# Guards a write with the Origin header instead of a CSRF token.
#
# THE TOKEN CANNOT WORK HERE, AND THAT IS NOT A BUG IN THE TOKEN.
# The kiosk story page exists to be framed by Home Assistant — see
# docs/adr/20260816-framed-by-home-assistant.md. A form on that page posts back
# to verso's own origin, so the *request* is same-origin, but the browsing
# context is a cross-site iframe, which makes verso's session cookie a
# third-party cookie. SameSite=Lax withholds it, Rails has no session to compare
# the token against, and every press of "Next picture" on the wall returned 422.
#
# WHY NOT JUST TURN FORGERY PROTECTION OFF.
# Because something should still stop a page on the internet driving the screens.
# A CSRF token protects a *credential* from being used by another site, and this
# app deliberately has none (docs/adr/20260816-no-auth-needed.md), so the token
# was only ever protecting the nuisance. The Origin header protects the same
# thing and survives the iframe: a browser sets it on every form POST and a
# hostile page cannot forge its own, so requiring it to equal this app's origin
# refuses exactly the request the token was there to refuse.
#
# WHY NOT SameSite=None.
# It would keep the token working, but it requires the cookie to be allowed as a
# third party — which an Android WebView may refuse outright — and a Secure
# cookie is not sent at all over the plain-http LAN address, so the browse UI's
# buttons would break there instead. Trading one broken surface for another.
module SameOriginWrite
  extend ActiveSupport::Concern

  included do
    skip_forgery_protection
    before_action :require_same_origin
  end

  private
    def require_same_origin
      # Reads are public by design — the feed is fetched cross-origin by the
      # kiosk's own script, and the browse pages are open. Only writes are
      # guarded, which is what this concern is named for.
      return if request.get? || request.head?

      # Browsers send Origin on every cross-origin *and* same-origin form POST.
      # A missing one means a client that is not a browser, which is not what
      # these routes are for.
      return if request.origin.present? && request.origin == request.base_url

      Rails.logger.warn(
        "[verso] refused a write from origin #{request.origin.inspect} " \
        "(expected #{request.base_url.inspect})"
      )
      head :forbidden
    end
end
