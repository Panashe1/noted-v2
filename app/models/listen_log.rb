class ListenLog < ApplicationRecord
  belongs_to :user
  belongs_to :album

  validates :rating,      presence: true, inclusion: { in: 1..10 }
  validates :listened_on, presence: true
  validates :user_id, uniqueness: {
    scope: :album_id,
    message: "you've already logged this album — edit your existing entry instead"
  }

  after_create :maybe_regenerate_taste_profile

  private

  def maybe_regenerate_taste_profile
    if user.listen_logs.count % 5 == 0
      user.regenerate_taste_profile!
    end
  end
end
