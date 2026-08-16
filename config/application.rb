require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Verso
  # Every directory verso reads or writes is configuration, never a literal in
  # the code. This app is public and other people will lay their disks out
  # their own way; a path baked into a model is a path they cannot change
  # without a fork.
  #
  # All three default to somewhere inside the app's own storage directory, so a
  # fresh clone runs with no configuration at all, and a deployment overrides
  # whichever ones it mounts elsewhere.

  # Kiosk browsers commonly serve their dashboard from a port on the device
  # itself, so the page framing verso is a loopback origin whose port belongs to
  # whichever kiosk app is installed. Allowing loopback outright means a kiosk
  # needs no configuration at all. It grants little: a page can only claim this
  # origin by already running on the viewer's own machine.
  LOOPBACK_FRAME_ANCESTORS = %w[ http://127.0.0.1:* http://localhost:* ].freeze

  # Origins allowed to embed verso in an iframe, from a comma-separated env var.
  # Empty (the default) means loopback and same-origin only. Feeds CSP's
  # frame-ancestors — see docs/adr/20260816-framed-by-home-assistant.md.
  def self.frame_ancestors(value = ENV["VERSO_FRAME_ANCESTORS"])
    value.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  # Where Active Storage keeps blobs. Read by config/storage.yml.
  def self.storage_root
    Pathname.new(ENV.fetch("VERSO_STORAGE_PATH") { Rails.root.join("storage").to_s })
  end

  # Where ArtworkExporter writes originals and its manifest — the copy of the
  # collection that does not need verso to be readable.
  def self.export_root
    Pathname.new(ENV.fetch("VERSO_EXPORT_PATH") { storage_root.join("export").to_s })
  end

  # The one directory tree file-delivery displays may write into. A Display's
  # file_path is relative to this and is not permitted to escape it: verso has
  # no authentication, so an absolute path in a database column would let
  # anyone who can reach the app overwrite any file the process can.
  def self.delivery_root
    Pathname.new(ENV.fetch("VERSO_DELIVERY_PATH") { storage_root.join("delivery").to_s })
  end

  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = ENV.fetch("TZ", "UTC")

    # Rails defaults to X-Frame-Options: SAMEORIGIN, which has no multi-origin
    # form and which browsers will not let you combine with CSP frame-ancestors.
    # The kiosk has to be able to frame the story page, so the header goes and
    # frame-ancestors takes over — see the initializer and
    # docs/adr/20260816-framed-by-home-assistant.md.
    config.action_dispatch.default_headers.delete("X-Frame-Options")

    # The running build's git SHA, written into REVISION by the Docker build and
    # absent in development. Shown in the footer, so a deploy that silently did
    # not land says so on the page instead of being debugged from the outside.
    revision       = Rails.root.join("REVISION")
    revision_short = Rails.root.join("REVISION_SHORT")
    config.x.git_sha       = revision.exist?       ? revision.read.strip       : "dev"
    config.x.git_sha_short = revision_short.exist? ? revision_short.read.strip : "dev"

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
