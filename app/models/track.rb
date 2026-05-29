class Track < ApplicationRecord
  belongs_to :album
  has_many :track_logs, dependent: :destroy

  validates :title, presence: true

  default_scope { order(:position) }

  # Average rating across all track logs that have a rating, rounded to 1 dp.
  # Returns nil when no rated logs exist yet.
  def average_rating
    track_logs.where.not(rating: nil).average(:rating)&.round(1)
  end

  # Total number of times this track has been logged (rated or not).
  def log_count
    track_logs.count
  end

  # Returns "3:45" formatted string, or nil if no duration
  def duration_formatted
    return nil unless duration_ms&.positive?

    total_seconds = duration_ms / 1000
    minutes = total_seconds / 60
    seconds = total_seconds % 60
    format("%d:%02d", minutes, seconds)
  end
end
