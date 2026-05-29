class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one_attached :avatar

  has_many :listen_logs, dependent: :destroy
  has_many :albums, through: :listen_logs
  has_many :track_logs, dependent: :destroy

  has_many :active_follows,  class_name: "Follow", foreign_key: :follower_id,  dependent: :destroy
  has_many :passive_follows, class_name: "Follow", foreign_key: :following_id, dependent: :destroy
  has_many :following, through: :active_follows,  source: :following
  has_many :followers, through: :passive_follows, source: :follower

  validates :username, presence: true, uniqueness: { case_sensitive: false },
                       format: { with: /\A[a-z0-9_]+\z/, message: "lowercase letters, numbers, underscores only" }
  validates :name, length: { maximum: 60 }, allow_blank: true
  validates :bio,  length: { maximum: 300 }, allow_blank: true
  validate  :avatar_content_type

  private

  def avatar_content_type
    return unless avatar.attached?
    unless avatar.content_type.in?(%w[image/jpeg image/png image/gif image/webp])
      errors.add(:avatar, "must be a JPEG, PNG, GIF, or WebP image")
    end
  end

  public

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
