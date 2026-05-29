require "test_helper"

class TrackLogsControllerTest < ActionDispatch::IntegrationTest
  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------
  # alice has a log for :paranoid_android; bob has no logs yet.

  def setup
    @alice          = users(:alice)
    @bob            = users(:bob)
    @track          = tracks(:karma_police)       # not yet logged by anyone
    @alices_log     = track_logs(:alice_paranoid_android)
    @alices_track   = tracks(:paranoid_android)
  end

  # ---------------------------------------------------------------------------
  # CREATE — logged-in user can log a track
  # ---------------------------------------------------------------------------

  test "logged-in user can create a track log and is redirected to the track page" do
    sign_in @bob

    assert_difference "TrackLog.count", 1 do
      post track_logs_path, params: {
        track_log: {
          track_id:    @track.id,
          listened_on: "2024-06-01",
          rating:      8
        }
      }
    end

    assert_redirected_to track_path(@track)
    follow_redirect!
    assert_match "Track logged", response.body
  end

  test "unauthenticated request to create redirects to sign-in" do
    assert_no_difference "TrackLog.count" do
      post track_logs_path, params: {
        track_log: {
          track_id:    @track.id,
          listened_on: "2024-06-01"
        }
      }
    end

    assert_redirected_to new_user_session_path
  end

  test "duplicate log returns an error redirect, not a 500" do
    sign_in @alice   # alice already has a log for paranoid_android

    assert_no_difference "TrackLog.count" do
      post track_logs_path, params: {
        track_log: {
          track_id:    @alices_track.id,
          listened_on: "2024-06-02"
        }
      }
    end

    # Must redirect (not 5xx) and carry an alert
    assert_response :redirect
    follow_redirect!
    assert_match(/already logged|edit your existing/i, response.body)
  end

  # ---------------------------------------------------------------------------
  # EDIT — user can only edit their own logs
  # ---------------------------------------------------------------------------

  test "user can access edit page for their own log" do
    sign_in @alice
    get edit_track_log_path(@alices_log)
    assert_response :success
  end

  test "user cannot access edit page for another user's log" do
    sign_in @bob   # bob does not own @alices_log

    # set_track_log calls current_user.track_logs.find → middleware converts
    # RecordNotFound to a 404 response in integration tests.
    get edit_track_log_path(@alices_log)
    assert_response :not_found
  end

  # ---------------------------------------------------------------------------
  # UPDATE — valid params update the log and redirect
  # ---------------------------------------------------------------------------

  test "update with valid params saves changes and redirects to track page" do
    sign_in @alice

    patch track_log_path(@alices_log), params: {
      track_log: {
        listened_on: "2024-07-04",
        rating:      10,
        review:      "Even better on relisten.",
        is_relisten: true
      }
    }

    assert_redirected_to track_path(@alices_track)
    @alices_log.reload
    assert_equal 10,                          @alices_log.rating
    assert_equal "Even better on relisten.",  @alices_log.review
    assert_equal true,                        @alices_log.is_relisten
  end

  test "update with invalid params re-renders edit with unprocessable_entity" do
    sign_in @alice

    patch track_log_path(@alices_log), params: {
      track_log: { listened_on: "" }   # listened_on is required
    }

    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------------------------
  # DESTROY — removes the log and redirects
  # ---------------------------------------------------------------------------

  test "destroy removes the log and redirects to the track page" do
    sign_in @alice

    assert_difference "TrackLog.count", -1 do
      delete track_log_path(@alices_log)
    end

    assert_redirected_to track_path(@alices_track)
    follow_redirect!
    assert_match "Log removed", response.body
  end

  test "user cannot destroy someone else's log" do
    sign_in @bob   # bob does not own @alices_log

    # Middleware converts RecordNotFound → 404 in integration tests.
    assert_no_difference "TrackLog.count" do
      delete track_log_path(@alices_log)
    end
    assert_response :not_found
  end
end
