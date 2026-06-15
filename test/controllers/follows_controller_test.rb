require "test_helper"

class FollowsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @alice = users(:alice)
    @bob   = users(:bob)
  end

  # ---------------------------------------------------------------------------
  # Profile page (source=profile) — answers with a Turbo Stream so the follower
  # count updates live without a page refresh.
  # ---------------------------------------------------------------------------

  test "following from a profile returns a turbo stream that updates the button and count" do
    sign_in @alice

    assert_difference -> { @bob.followers.count }, 1 do
      post follow_user_path(@bob.username, source: "profile"),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_match "follow_#{@bob.id}", response.body
    assert_match "profile-followers-count", response.body
  end

  test "unfollowing from a profile returns a turbo stream and drops the follower" do
    @alice.active_follows.create!(following: @bob)
    sign_in @alice

    assert_difference -> { @bob.followers.count }, -1 do
      delete unfollow_user_path(@bob.username, source: "profile"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_match "profile-followers-count", response.body
  end

  # ---------------------------------------------------------------------------
  # Other contexts (Find People, follows modal) — no source param, so the
  # controller keeps the plain redirect + turbo-frame swap.
  # ---------------------------------------------------------------------------

  test "following without a source redirects to the profile" do
    sign_in @alice

    assert_difference -> { @bob.followers.count }, 1 do
      post follow_user_path(@bob.username)
    end

    assert_redirected_to user_path(@bob.username)
  end
end
