class Album < ApplicationRecord
  has_many :listen_logs, dependent: :destroy
  has_many :listeners, through: :listen_logs, source: :user
  has_many :tracks, dependent: :destroy

  validates :title,  presence: true
  validates :artist, presence: true

  after_create :enqueue_context_generation
  after_create :enqueue_track_import, if: :itunes_id?

  def average_rating
    listen_logs.average(:rating)&.round(1)
  end

  def log_count
    listen_logs.count
  end

  # Returns cover art URL or nil; iTunes gives 100x100, we upscale to 600x600
  def cover_url(size: 600)
    return nil unless cover_image_url.present?

    cover_image_url.gsub(/\d+x\d+bb/, "#{size}x#{size}bb")
  end

  private

  def enqueue_context_generation
    AlbumContextJob.perform_later(id)
  end

  def enqueue_track_import
    TrackImportJob.perform_later(id)
  end
end
