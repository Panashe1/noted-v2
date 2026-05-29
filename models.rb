# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :listen_logs, dependent: :destroy
  has_many :albums, through: :listen_logs

  # Follows (self-referential)
  has_many :active_follows,   class_name: "Follow", foreign_key: :follower_id,  dependent: :destroy
  has_many :passive_follows,  class_name: "Follow", foreign_key: :following_id, dependent: :destroy
  has_many :following, through: :active_follows,  source: :following
  has_many :followers, through: :passive_follows, source: :follower

  validates :username, presence: true, uniqueness: { case_sensitive: false },
                       format: { with: /\A[a-z0-9_]+\z/, message: "lowercase letters, numbers, underscores only" }

  # Regenerate taste profile when user logs enough albums
  def regenerate_taste_profile!
    TasteProfileJob.perform_later(id)
  end

  def logged?(album)
    listen_logs.exists?(album: album)
  end

  def average_rating
    listen_logs.average(:rating)&.round(1)
  end
end

# app/models/album.rb
class Album < ApplicationRecord
  has_many :listen_logs, dependent: :destroy
  has_many :listeners, through: :listen_logs, source: :user

  validates :title,  presence: true
  validates :artist, presence: true

  after_create :enqueue_context_generation

  def average_rating
    listen_logs.average(:rating)&.round(1)
  end

  def log_count
    listen_logs.count
  end

  private

  def enqueue_context_generation
    AlbumContextJob.perform_later(id)
  end
end

# app/models/listen_log.rb
class ListenLog < ApplicationRecord
  belongs_to :user
  belongs_to :album

  validates :rating, presence: true, inclusion: { in: 1..10 }
  validates :listened_on, presence: true
  validates :user_id, uniqueness: {
    scope: :album_id,
    message: "you've already logged this album — edit your existing entry instead"
  }

  after_create :maybe_regenerate_taste_profile

  private

  def maybe_regenerate_taste_profile
    # Regenerate after every 5th log entry
    if user.listen_logs.count % 5 == 0
      user.regenerate_taste_profile!
    end
  end
end

# app/models/follow.rb
class Follow < ApplicationRecord
  belongs_to :follower,  class_name: "User"
  belongs_to :following, class_name: "User"

  validates :follower_id, uniqueness: { scope: :following_id }
  validate  :cannot_follow_self

  private

  def cannot_follow_self
    errors.add(:base, "You can't follow yourself") if follower_id == following_id
  end
end
