# frame-ancestors is the only directive in the policy.
#
# default_src and script_src would break the importmap and Turbo setup, and
# there is no untrusted content in verso to defend against with them. What is
# needed is narrow: the household dashboard has to be allowed to embed the story
# page in an iframe, which X-Frame-Options cannot express — see
# docs/adr/20260816-framed-by-home-assistant.md.
#
# Application-wide rather than scoped to the kiosk route. Scoping would be a
# false economy: the same screen will plausibly want another page next, and a
# per-controller policy is more machinery than the risk warrants on a LAN-only
# app with no login.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.frame_ancestors :self, *Verso::LOOPBACK_FRAME_ANCESTORS, *Verso.frame_ancestors
  end
end
