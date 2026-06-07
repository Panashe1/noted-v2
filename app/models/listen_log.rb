class ListenLog < ApplicationRecord
  belongs_to :user
  belongs_to :album

  validates :rating,      presence: true, inclusion: { in: 1..10 }
  validates :listened_on, presence: true
  validate  :listened_on_not_in_future

  private

  def listened_on_not_in_future
    return unless listened_on.present?
    errors.add(:listened_on, :future) if listened_on > Date.current
  end

  public
  validates :user_id, uniqueness: {
    scope: :album_id,
    message: :taken_album
  }

  after_create :maybe_regenerate_taste_profile

  private

  def maybe_regenerate_taste_profile
    if user.listen_logs.count % 5 == 0
      user.regenerate_taste_profile!
    end
  end
end
