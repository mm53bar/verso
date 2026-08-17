ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  # Writes are guarded by the Origin header rather than a CSRF token, because the
  # kiosk page is framed cross-site — see SameOriginWrite. A browser sets this on
  # every form POST; a test that omits it is testing a client that is not one.
  BROWSER = { "HTTP_ORIGIN" => "http://www.example.com" }.freeze
end
