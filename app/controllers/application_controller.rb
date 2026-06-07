class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  around_action :switch_locale
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  # Runs every request inside the locale taken from the URL (:locale param).
  # The route constraint guarantees it is one of the available locales, or nil
  # (the default, unprefixed locale).
  def switch_locale(&action)
    locale = params[:locale] || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  # Keep the active locale in every generated URL. The default locale is omitted
  # so its URLs stay clean (/albums rather than /en/albums).
  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username, :bio, :favourite_genre])
  end

  private

  # Returns a Hash { track_id => avg_rating } for the given collection of tracks.
  # Executes exactly one SQL query regardless of collection size — use this any time
  # a view needs per-track aggregate scores to avoid N+1 queries.
  def preload_track_ratings(tracks)
    ids = Array(tracks).map(&:id)
    return {} if ids.empty?

    TrackLog.where(track_id: ids)
            .where.not(rating: nil)
            .group(:track_id)
            .average(:rating)
            .transform_values { |v| v.round(1) }
  end
end
