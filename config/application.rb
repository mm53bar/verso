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

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
