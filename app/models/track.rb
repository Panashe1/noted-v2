class Track < ApplicationRecord
  belongs_to :album
  has_many :track_logs, dependent: :destroy

  validates :title, presence: true

  default_scope { order(:position) }

  # Returns "3:45" formatted string, or nil if no duration
  def duration_formatted
    return nil unless duration_ms&.positive?

    total_seconds = duration_ms / 1000
    minutes = total_seconds / 60
    seconds = total_seconds % 60
    format("%d:%02d", minutes, seconds)
  end
end
