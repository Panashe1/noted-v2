class FollowsController < ApplicationController
  def create
    user = User.find_by!(username: params[:username])
    current_user.active_follows.find_or_create_by(following: user)
    redirect_to user_path(user.username)
  end

  def destroy
    user = User.find_by!(username: params[:username])
    current_user.active_follows.find_by(following: user)&.destroy
    redirect_to user_path(user.username)
  end
end
