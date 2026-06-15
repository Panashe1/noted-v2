class FollowsController < ApplicationController
  def create
    @user = User.find_by!(username: params[:username])
    current_user.active_follows.find_or_create_by(following: @user)
    respond_to_follow_change(following: true)
  end

  def destroy
    @user = User.find_by!(username: params[:username])
    current_user.active_follows.find_by(following: @user)&.destroy
    respond_to_follow_change(following: false)
  end

  private

  # The profile page needs the follower count to update live, so it sends ?source=profile
  # and we answer with a Turbo Stream that swaps both the button and the count. Other
  # contexts (Find People, the follows modal) only have a button to toggle, so the simple
  # redirect + turbo-frame swap is enough and keeps their context-specific styling.
  def respond_to_follow_change(following:)
    @following = following
    if params[:source] == "profile"
      respond_to do |format|
        format.turbo_stream { render :follow_change }
        format.html { redirect_to user_path(@user.username) }
      end
    else
      redirect_to user_path(@user.username)
    end
  end
end
