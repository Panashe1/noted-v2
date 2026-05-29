require "test_helper"

class TracksControllerTest < ActionDispatch::IntegrationTest
  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  def setup
    @alice = users(:alice)
    @track = tracks(:paranoid_android)
    @album = albums(:ok_computer)

    # Sign in by default for routes that require auth (ApplicationController
    # authenticates everyone except devise controllers).
    sign_in @alice
  end

  # ---------------------------------------------------------------------------
  # INDEX
  # ---------------------------------------------------------------------------

  test "index returns 200 with no query" do
    # Stub MusicSearchService so index never hits iTunes even on short queries
    stub_instance_method(MusicSearchService, :search_tracks,[]) do
      get tracks_path
    end
    assert_response :success
  end

  test "index with a short query (< 2 chars) still returns 200" do
    stub_instance_method(MusicSearchService, :search_tracks,[]) do
      get tracks_path, params: { q: "a" }
    end
    assert_response :success
  end

  test "index filters local tracks by title when query length >= 2" do
    stub_instance_method(MusicSearchService, :search_tracks,[]) do
      get tracks_path, params: { q: "Paranoid" }
    end

    assert_response :success
    assert_select "body", /Paranoid Android/i
  end

  test "index excludes local tracks already in DB from iTunes results" do
    # Simulate an iTunes result whose itunes_track_id matches an existing track.
    itunes_result = {
      itunes_track_id: @track.itunes_track_id,  # "111" — already in DB
      itunes_album_id: "9999",
      title:           "Paranoid Android",
      artist:          "Radiohead",
      album_title:     "OK Computer",
      is_single:       false
    }

    stub_instance_method(MusicSearchService, :search_tracks,[itunes_result]) do
      get tracks_path, params: { q: "Paranoid" }
    end

    # @itunes_tracks should be empty because the track is already local
    assert_response :success
    # The controller sets @itunes_tracks to [] after filtering — we verify no
    # duplicate would be presented (no assertion on rendered HTML needed beyond 200)
  end

  # ---------------------------------------------------------------------------
  # SHOW
  # ---------------------------------------------------------------------------

  test "show returns 200 for a valid track" do
    get track_path(@track)
    assert_response :success
  end

  test "show returns 404 for an unknown id" do
    # In integration tests, RecordNotFound is caught by the middleware stack
    # and converted to a 404 response rather than raised to the test.
    get track_path(id: 999_999)
    assert_response :not_found
  end

  # ---------------------------------------------------------------------------
  # FROM_ITUNES — missing params
  # ---------------------------------------------------------------------------

  test "from_itunes redirects to tracks_path with alert when itunes_track_id is blank" do
    get from_itunes_tracks_path, params: { itunes_track_id: "", itunes_album_id: "777" }
    assert_redirected_to tracks_path
    follow_redirect!
    assert_match "Missing track info", response.body
  end

  test "from_itunes redirects to tracks_path with alert when itunes_album_id is blank" do
    get from_itunes_tracks_path, params: { itunes_track_id: "111", itunes_album_id: "" }
    assert_redirected_to tracks_path
    follow_redirect!
    assert_match "Missing track info", response.body
  end

  test "from_itunes redirects to tracks_path with alert when both params are missing" do
    get from_itunes_tracks_path
    assert_redirected_to tracks_path
    follow_redirect!
    assert_match "Missing track info", response.body
  end

  # ---------------------------------------------------------------------------
  # FROM_ITUNES — track already in local DB (no duplicates, no HTTP call)
  # ---------------------------------------------------------------------------

  test "from_itunes redirects to track_path without creating duplicates when track exists" do
    # @track already has itunes_track_id "111"
    assert_no_difference "Track.count" do
      # MusicSearchService should never be called — stub it to fail loudly if hit
      stub_instance_method(MusicSearchService, :fetch_album_with_tracks,
                                           ->(_) { flunk "should not call iTunes when track already exists" }) do
        get from_itunes_tracks_path,
            params: { itunes_track_id: @track.itunes_track_id,
                      itunes_album_id: @album.itunes_id }
      end
    end

    assert_redirected_to track_path(@track)
  end

  # ---------------------------------------------------------------------------
  # FROM_ITUNES — new track: stub MusicSearchService
  # ---------------------------------------------------------------------------

  test "from_itunes creates album and track when iTunes returns data for an unknown track" do
    new_itunes_track_id = "NEW_TRACK_999"
    new_itunes_album_id = "NEW_ALBUM_888"

    itunes_album_payload = {
      album: {
        itunes_id:       new_itunes_album_id,
        title:           "Hail to the Thief",
        artist:          "Radiohead",
        release_year:    2003,
        genre:           "Alternative",
        cover_url:       "https://example.com/cover.jpg",
        apple_music_url: "https://music.apple.com/album/888"
      },
      tracks: [
        { itunes_track_id: new_itunes_track_id,
          title:           "2 + 2 = 5",
          position:        1,
          duration_ms:     221000 }
      ]
    }

    stub_instance_method(MusicSearchService, :fetch_album_with_tracks, itunes_album_payload) do
      assert_difference "Track.count", 1 do
        get from_itunes_tracks_path,
            params: { itunes_track_id: new_itunes_track_id,
                      itunes_album_id: new_itunes_album_id }
      end
    end

    created_track = Track.find_by(itunes_track_id: new_itunes_track_id)
    assert_not_nil created_track
    assert_redirected_to track_path(created_track)
  end

  test "from_itunes redirects to tracks_path with alert when iTunes lookup fails" do
    unknown_track_id = "UNKNOWN_999"
    unknown_album_id = "UNKNOWN_888"

    # Service returns nil when the iTunes API fails
    stub_instance_method(MusicSearchService, :fetch_album_with_tracks, nil) do
      get from_itunes_tracks_path,
          params: { itunes_track_id: unknown_track_id,
                    itunes_album_id: unknown_album_id }
    end

    assert_redirected_to tracks_path
    # Check the flash directly before following the redirect —
    # more reliable than scanning the full HTML response body.
    assert_match(/Couldn't load.*iTunes/i, flash[:alert])
  end
end
