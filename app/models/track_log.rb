class TrackLog < ApplicationRecord
  belongs_to :user
  belongs_to :track

  validates :listened_on, presence: true
  validates :rating, numericality: { in: 1..10, only_integer: true }, allow_nil: true
  validate  :listened_on_not_in_future

  private

  def listened_on_not_in_future
    return unless listened_on.present?
    errors.add(:listened_on, "can't be in the future") if listened_on > Date.current
  end

  public
  validates :user_id, uniqueness: {
    scope: :track_id,
    message: "you've already logged this track — edit your existing entry instead"
  }

  # Intentionally no after_create taste-profile callback —
  # track logs are separate from the album-based taste system.
end
