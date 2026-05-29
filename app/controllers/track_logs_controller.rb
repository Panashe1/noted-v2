class TrackLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_track_log, only: [:edit, :update, :destroy]

  def create
    # Bug fix: use find_by + early redirect instead of find, which raises 500 on bad/missing id
    @track = Track.find_by(id: track_log_params[:track_id])
    unless @track
      redirect_to tracks_path, alert: "Track not found." and return
    end
    @track_log = current_user.track_logs.new(track_log_params)

    if @track_log.save
      redirect_to track_path(@track), notice: "Track logged!"
    else
      redirect_to track_path(@track), alert: @track_log.errors.full_messages.first
    end
  end

  def edit
    @track = @track_log.track
  end

  def update
    @track = @track_log.track  # Bug fix: @track must be set before re-rendering :edit
    if @track_log.update(track_log_params)
      redirect_to track_path(@track), notice: "Log updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    track = @track_log.track
    @track_log.destroy
    redirect_to track_path(track), notice: "Log removed."
  end

  private

  def set_track_log
    @track_log = current_user.track_logs.find(params[:id])
  end

  def track_log_params
    params.require(:track_log).permit(:track_id, :listened_on, :rating, :review, :is_relisten)
  end
end
