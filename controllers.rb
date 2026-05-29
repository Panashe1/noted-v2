# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username, :bio, :favourite_genre])
  end
end

# ---------------------------------------------------------------------------

# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def index
    @recent_logs    = current_user.listen_logs.includes(:album).order(listened_on: :desc).limit(10)
    @following_logs = ListenLog.includes(:user, :album)
                               .where(user: current_user.following)
                               .order(created_at: :desc)
                               .limit(20)
    @taste_profile  = current_user.ai_taste_profile
  end
end

# ---------------------------------------------------------------------------

# app/controllers/listen_logs_controller.rb
class ListenLogsController < ApplicationController
  before_action :set_log, only: [:show, :edit, :update, :destroy]

  def create
    @album = find_or_create_album
    @log   = current_user.listen_logs.build(log_params.merge(album: @album))

    if @log.save
      redirect_to album_path(@album), notice: "Logged!"
    else
      redirect_back fallback_location: root_path, alert: @log.errors.full_messages.to_sentence
    end
  end

  def update
    if @log.update(log_params)
      redirect_to album_path(@log.album), notice: "Updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @log.destroy
    redirect_back fallback_location: root_path, notice: "Log removed."
  end

  # POST /listen_logs/assist_review
  # Returns an AI-drafted review via Turbo Stream
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
    Album.find_or_create_by(
      title:  params[:album][:title].strip,
      artist: params[:album][:artist].strip
    ) do |a|
      a.release_year     = params[:album][:release_year]
      a.genre            = params[:album][:genre]
      a.cover_image_url  = params[:album][:cover_image_url]
    end
  end
end

# ---------------------------------------------------------------------------

# app/controllers/albums_controller.rb
class AlbumsController < ApplicationController
  def show
    @album     = Album.find(params[:id])
    @logs      = @album.listen_logs.includes(:user).order(created_at: :desc)
    @user_log  = current_user.listen_logs.find_by(album: @album)
  end

  def index
    @albums = Album.order(created_at: :desc).page(params[:page])
  end
end

# ---------------------------------------------------------------------------

# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def show
    @user       = User.find_by!(username: params[:username])
    @logs       = @user.listen_logs.includes(:album).order(listened_on: :desc)
    @is_following = current_user.following.include?(@user)
  end
end

# ---------------------------------------------------------------------------

# app/controllers/recommendations_controller.rb
class RecommendationsController < ApplicationController
  def index
    @query = params[:q]
    if @query.present?
      @response = ClaudeService.new.recommend(user: current_user, query: @query)
    end
  end
end

# ---------------------------------------------------------------------------

# app/controllers/follows_controller.rb
class FollowsController < ApplicationController
  def create
    user = User.find_by!(username: params[:username])
    current_user.active_follows.find_or_create_by(following: user)
    redirect_back fallback_location: user_path(user)
  end

  def destroy
    user = User.find_by!(username: params[:username])
    current_user.active_follows.find_by(following: user)&.destroy
    redirect_back fallback_location: user_path(user)
  end
end
