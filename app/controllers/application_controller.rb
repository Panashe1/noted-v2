class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

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
