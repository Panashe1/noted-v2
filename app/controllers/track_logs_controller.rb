class TrackLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_track_log, only: [:edit, :update, :destroy]

  def create
    @track    = Track.find(track_log_params[:track_id])
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
    if @track_log.update(track_log_params)
      redirect_to track_path(@track_log.track), notice: "Log updated!"
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
