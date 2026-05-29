class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :listen_logs, dependent: :destroy
  has_many :albums, through: :listen_logs
  has_many :track_logs, dependent: :destroy

  has_many :active_follows,  class_name: "Follow", foreign_key: :follower_id,  dependent: :destroy
  has_many :passive_follows, class_name: "Follow", foreign_key: :following_id, dependent: :destroy
  has_many :following, through: :active_follows,  source: :following
  has_many :followers, through: :passive_follows, source: :follower

  validates :username, presence: true, uniqueness: { case_sensitive: false },
                       format: { with: /\A[a-z0-9_]+\z/, message: "lowercase letters, numbers, underscores only" }

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
