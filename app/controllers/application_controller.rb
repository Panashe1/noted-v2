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

  # Returns a Hash { album_id => { count:, avg: } } of listen-log stats for the given
  # albums (count = Album#log_count, avg = Album#average_rating). Two grouped SQL
  # queries total, regardless of collection size — avoids the per-album N+1 in the
  # albums grid and chart list. Unknown ids fall back to { count: 0, avg: nil }.
  def preload_album_stats(albums)
    blank = { count: 0, avg: nil }.freeze
    ids   = Array(albums).map(&:id).uniq
    return Hash.new(blank) if ids.empty?

    counts = ListenLog.where(album_id: ids).group(:album_id).count
    avgs   = ListenLog.where(album_id: ids).group(:album_id).average(:rating)

    stats = ids.index_with { |id| { count: counts[id] || 0, avg: avgs[id]&.round(1) } }
    stats.default = blank
    stats
  end

  # Returns a Hash { user_id => listen_logs_count } for the given users in one query.
  # Missing users default to 0.
  def preload_user_log_counts(users)
    ids = Array(users).map(&:id).uniq
    counts = ids.empty? ? {} : ListenLog.where(user_id: ids).group(:user_id).count
    counts.tap { |h| h.default = 0 }
  end

  # Returns a Hash { user_id => follower_count } for the given users in one query.
  # Missing users default to 0.
  def preload_follower_counts(users)
    ids = Array(users).map(&:id).uniq
    counts = ids.empty? ? {} : Follow.where(following_id: ids).group(:following_id).count
    counts.tap { |h| h.default = 0 }
  end
end
