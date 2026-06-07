class ListenLogsController < ApplicationController
  before_action :set_log, only: [:edit, :update, :destroy]

  def create
    @album = find_or_create_album
    @log   = current_user.listen_logs.build(log_params.merge(album: @album))

    if @log.save
      redirect_to album_path(@album), notice: t("flash.listen_logs.created")
    else
      redirect_back fallback_location: root_path, alert: @log.errors.full_messages.to_sentence
    end
  end

  def edit
  end

  def update
    if @log.update(log_params)
      redirect_to album_path(@log.album), notice: t("flash.listen_logs.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @log.destroy
    redirect_back fallback_location: root_path, notice: t("flash.listen_logs.removed")
  end

  def assist_review
    album  = Album.find(params[:album_id])
    rating = params[:rating].to_i
    notes  = params[:notes]

    draft = ClaudeService.new.assist_review(album: album, rating: rating, user_notes: notes)

    render json: { draft: draft }
  end

  private

  def set_log
    @log = current_user.listen_logs.find(params[:id])
  end

  def log_params
    params.require(:listen_log).permit(:rating, :review, :listened_on, :is_relisten)
  end

  def find_or_create_album
    itunes_id = params[:album][:itunes_id].presence

    # If we have an iTunes ID, try matching on that first (most precise)
    if itunes_id
      album = Album.find_by(itunes_id: itunes_id)
      return album if album
    end

    Album.find_or_create_by(
      title:  params[:album][:title].to_s.strip,
      artist: params[:album][:artist].to_s.strip
    ) do |a|
      a.release_year    = params[:album][:release_year].presence
      a.genre           = params[:album][:genre].presence
      a.cover_image_url = params[:album][:cover_image_url].presence
      a.itunes_id       = itunes_id
      a.apple_music_url = params[:album][:apple_music_url].presence
    end
  end
end
