ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# ── Minitest 6 / Rails 7.2 compatibility ─────────────────────────────────────
# Rails' LineFiltering patch defines `run(reporter, options={})` (2 args max).
# Minitest 6 changed the runner to call `run(reporter, reporter, options)` —
# 3 args — which raises ArgumentError.  Splat-accepting override fixes it.
if Gem::Version.new(Minitest::VERSION) >= Gem::Version.new("6")
  module Rails
    module LineFiltering
      def run(reporter, *args)
        super
      end
    end
  end
end

# The app's routes are wrapped in an optional (:locale) scope. In the running app,
# ApplicationController#default_url_options supplies :locale so positional route args
# (e.g. track_path(@track)) fill :id. Test-context url helpers (both the directly
# included helpers and those proxied to the integration session) don't inherit that,
# so the positional arg gets consumed by the optional :locale segment and raises
# UrlGenerationError. Providing :locale on the route set itself covers every path;
# a per-request controller (e.g. for :es) still overrides this.
Rails.application.routes.default_url_options[:locale] = nil

# Devise test helpers for controller/integration tests
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end

class ActionController::TestCase
  include Devise::Test::ControllerHelpers
end

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Load fixtures from test/fixtures
  fixtures :all

  # Quick helper: build a minimal valid TrackLog hash for params
  def valid_track_log_params(track:, overrides: {})
    {
      track_log: {
        track_id:    track.id,
        listened_on: Date.today.iso8601,
        rating:      nil,
        review:      nil,
        is_relisten: false
      }.merge(overrides)
    }
  end

  # Temporarily overrides an instance method on a class for the duration of a block.
  # Replacement for stub_any_instance which isn't available in Minitest 6.
  #
  #   stub_instance_method(MusicSearchService, :search_tracks, []) { ... }
  #   stub_instance_method(MusicSearchService, :fetch_album_with_tracks, ->(_id) { nil }) { ... }
  #
  def stub_instance_method(klass, method_name, return_value_or_callable, &block)
    original = klass.instance_method(method_name)
    callable = return_value_or_callable.respond_to?(:call) ?
      return_value_or_callable : ->(*_) { return_value_or_callable }
    klass.define_method(method_name, callable)
    block.call
  ensure
    klass.define_method(method_name, original)
  end
end
