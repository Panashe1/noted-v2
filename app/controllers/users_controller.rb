class UsersController < ApplicationController
  before_action :authenticate_user!, only: [:home, :search, :settings, :update_settings]
  before_action :require_own_profile, only: [:settings, :update_settings]

  # Root redirect — sends signed-in users to their own profile
  def home
    redirect_to user_path(current_user.username)
  end

  def settings
    @user = current_user
  end

  def update_settings
    @user = current_user
    if @user.update(settings_params)
      redirect_to user_path(@user.username), notice: t("flash.users.profile_updated")
    else
      render :settings, status: :unprocessable_entity
    end
  end

  private

  def require_own_profile
    unless current_user.username == params[:username]
      redirect_to user_path(current_user.username), alert: t("flash.users.not_authorised")
    end
  end

  def settings_params
    params.require(:user).permit(:name, :bio, :avatar)
  end

  # Preloads current_user's follow relationships into two Sets so the
  # follow-list partial can determine button state in O(1) without extra queries.
  def prep_follow_sets
    if user_signed_in?
      @my_following_ids = current_user.following.pluck(:id).to_set
      @my_follower_ids  = current_user.followers.pluck(:id).to_set
    else
      @my_following_ids = Set.new
      @my_follower_ids  = Set.new
    end
  end

  public

  def search
    @query = params[:q].to_s.strip

    @results = if @query.length >= 2
      User.where("username ILIKE ?", "%#{@query}%")
          .where.not(id: current_user.id)
          .order(:username)
          .limit(20)
    else
      User.none
    end

    # Preload aggregates so the results partial avoids a per-user N+1
    # (log count, follower count, and follow-button state).
    prep_follow_sets
    @log_counts      = preload_user_log_counts(@results)
    @follower_counts = preload_follower_counts(@results)

    locals = {
      results:         @results,
      query:           @query,
      log_counts:      @log_counts,
      follower_counts: @follower_counts,
      following_ids:   @my_following_ids
    }

    respond_to do |format|
      format.html
      format.turbo_stream { render partial: "users/search_results", locals: locals }
    end
  end

  # GET /u/:username/following  (no layout — injected into modal)
  def following
    @user = User.find_by!(username: params[:username])
    @list = @user.following.order(:username)
    prep_follow_sets
    @list_log_counts = preload_user_log_counts(@list)
    render layout: false
  end

  # GET /u/:username/followers  (no layout — injected into modal)
  def followers
    @user = User.find_by!(username: params[:username])
    @list = @user.followers.order(:username)
    prep_follow_sets
    @list_log_counts = preload_user_log_counts(@list)
    render layout: false
  end

  def show
    @user = User.find_by!(username: params[:username])

    # Common data
    @logs         = @user.listen_logs.includes(:album).order(listened_on: :desc)
    @track_logs   = @user.track_logs.includes(track: :album).order(listened_on: :desc)
    @is_following = current_user&.following&.include?(@user) || false

    # Extra data only loaded when viewing your own profile
    if user_signed_in? && @user == current_user
      @own_profile     = true
      @recent_logs     = @logs.first(20)
      @following_logs  = ListenLog.includes(:user, :album)
                                  .where(user: current_user.following)
                                  .order(created_at: :desc)
                                  .limit(20)
      @taste_profile   = current_user.ai_taste_profile
    end
  end
end
