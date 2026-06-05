require "test_helper"

class AlbumGenreFilterTest < ActionDispatch::IntegrationTest
  def setup
    sign_in users(:alice)

    TrackLog.delete_all
    Track.delete_all
    ListenLog.delete_all
    Album.delete_all

    Album.create!(title: "ZRock1",   artist: "A", genre: "Rock")
    Album.create!(title: "ZRock2",   artist: "B", genre: "Rock")
    Album.create!(title: "ZPop1",    artist: "C", genre: "Pop")
    Album.create!(title: "ZHipHop1", artist: "D", genre: "Hip-Hop/Rap")
    Album.create!(title: "ZNone1",   artist: "E", genre: nil)
  end

  # Stub the iTunes charts call so the index never hits the network.
  def get_index(params = {})
    stub_instance_method(MusicSearchService, :fetch_top_albums, []) do
      get albums_path(params)
    end
  end

  test "no filter shows every album" do
    get_index
    assert_response :success
    %w[ZRock1 ZRock2 ZPop1 ZHipHop1 ZNone1].each { |t| assert_match t, response.body }
  end

  test "single genre shows only that genre" do
    get_index(genres: ["Rock"])
    assert_response :success
    assert_match "ZRock1", response.body
    assert_match "ZRock2", response.body
    assert_no_match "ZPop1",    response.body
    assert_no_match "ZHipHop1", response.body
    assert_no_match "ZNone1",   response.body
  end

  test "stacked genres OR-filter across both" do
    get_index(genres: ["Rock", "Pop"])
    assert_match "ZRock1", response.body
    assert_match "ZRock2", response.body
    assert_match "ZPop1",  response.body
    assert_no_match "ZHipHop1", response.body
    assert_no_match "ZNone1",   response.body
  end

  test "genre containing slash and dash filters correctly" do
    get_index(genres: ["Hip-Hop/Rap"])
    assert_match "ZHipHop1", response.body
    assert_no_match "ZRock1", response.body
  end

  test "garbage genre values are sanitised, valid one still applies" do
    get_index(genres: ["Rock", "'; DROP TABLE albums; --", "Nonexistent"])
    assert_response :success
    assert_match "ZRock1", response.body
    assert_no_match "ZPop1", response.body
  end

  test "filtering by a genre that has no albums is ignored and shows all" do
    Album.where(genre: "Pop").delete_all
    get_index(genres: ["Pop"])
    assert_response :success
    # "Pop" is no longer an available genre, so it's sanitised out and the filter is dropped.
    assert_match "ZRock1",   response.body
    assert_match "ZHipHop1", response.body
  end

  test "turbo frame request does NOT call the iTunes charts service" do
    # Flunk if fetch_top_albums is invoked — proves the frame path skips it.
    stub_instance_method(MusicSearchService, :fetch_top_albums, ->(*) { flunk "charts should be skipped on a frame request" }) do
      get albums_path(genres: ["Rock"]), headers: { "Turbo-Frame" => "community-library" }
    end
    assert_response :success
    assert_match "ZRock1", response.body
  end

  test "full page request DOES render the charts section" do
    stub_instance_method(MusicSearchService, :fetch_top_albums,
      [{ itunes_id: "1", title: "ChartHit", artist: "X", release_year: 2024, genre: "Pop", cover_url: nil, apple_music_url: nil, chart_rank: 1 }]) do
      get albums_path
    end
    assert_match "Top Albums", response.body
    assert_match "ChartHit",   response.body
  end

  test "album cards break out of the filter frame to avoid Turbo 'Content missing'" do
    # Album cards link to the show page, which has no community-library frame —
    # they must carry data-turbo-frame=_top so they navigate the whole page.
    get_index(genres: ["Rock"])
    rock = Album.find_by(title: "ZRock1")
    # Must target _top so the card navigates the whole page instead of loading the
    # show page (which has no community-library frame) into the filter frame.
    assert_select %(a[href="#{album_path(rock)}"][data-turbo-frame="_top"])
  end
end
