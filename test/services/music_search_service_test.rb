require "test_helper"
require "ostruct"

class MusicSearchServiceTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Builds a minimal fake HTTParty response object.
  #
  #   fake_response(success: true, body: { ... })
  #   fake_response(success: false, code: 500)
  #
  def fake_response(success:, body: nil, code: 200)
    body_str = body ? body.to_json : ""
    OpenStruct.new(success?: success, body: body_str, code: code)
  end

  # Temporarily replaces HTTParty.get with a callable or fixed return value.
  # Minitest 6 removed Object#stub so we use define_singleton_method + cleanup.
  def stub_httparty(return_value_or_callable, &block)
    original = HTTParty.singleton_method(:get)
    callable = return_value_or_callable.respond_to?(:call) ? return_value_or_callable : ->(*_) { return_value_or_callable }
    HTTParty.define_singleton_method(:get, callable)
    block.call
  ensure
    HTTParty.define_singleton_method(:get, original)
  end

  # A realistic iTunes "song" result hash
  def itunes_song_result(overrides = {})
    {
      "wrapperType"    => "track",
      "kind"           => "song",
      "trackId"        => 123_456,
      "collectionId"   => 789_012,
      "trackName"      => "Creep",
      "artistName"     => "Radiohead",
      "collectionName" => "Pablo Honey",
      "collectionType" => "Album",
      "trackNumber"    => 5,
      "trackTimeMillis"=> 238_000,
      "artworkUrl100"  => "https://example.com/100x100bb.jpg",
      "releaseDate"    => "1993-02-22T00:00:00Z",
      "primaryGenreName" => "Alternative"
    }.merge(overrides)
  end

  # A realistic iTunes "collection" (album) result hash
  def itunes_album_result(overrides = {})
    {
      "wrapperType"    => "collection",
      "collectionId"   => 789_012,
      "collectionName" => "Pablo Honey",
      "artistName"     => "Radiohead",
      "releaseDate"    => "1993-02-22T00:00:00Z",
      "primaryGenreName" => "Alternative",
      "artworkUrl100"  => "https://example.com/100x100bb.jpg",
      "collectionViewUrl" => "https://music.apple.com/album/789012",
      "trackCount"     => 12
    }.merge(overrides)
  end

  def service
    @service ||= MusicSearchService.new
  end

  # ---------------------------------------------------------------------------
  # search_tracks — blank / empty query
  # ---------------------------------------------------------------------------

  test "search_tracks returns [] for a blank query" do
    # No HTTP call should be made
    stub_httparty(->(*_args) { flunk "HTTParty.get should not be called" }) do
      result = service.search_tracks("")
      assert_equal [], result
    end
  end

  test "search_tracks returns [] for a nil query" do
    stub_httparty(->(*_args) { flunk "HTTParty.get should not be called" }) do
      result = service.search_tracks(nil)
      assert_equal [], result
    end
  end

  test "search_tracks returns [] for a whitespace-only query" do
    stub_httparty(->(*_args) { flunk "HTTParty.get should not be called" }) do
      result = service.search_tracks("   ")
      assert_equal [], result
    end
  end

  # ---------------------------------------------------------------------------
  # search_tracks — successful HTTP response: field parsing
  # ---------------------------------------------------------------------------

  test "search_tracks parses itunes_track_id from trackId" do
    body = { "results" => [itunes_song_result] }
    resp = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("creep")
      assert_equal 1, results.size
      assert_equal "123456", results.first[:itunes_track_id]
    end
  end

  test "search_tracks parses itunes_album_id from collectionId" do
    body = { "results" => [itunes_song_result] }
    resp = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("creep")
      assert_equal "789012", results.first[:itunes_album_id]
    end
  end

  test "search_tracks parses title, artist, and album_title" do
    body = { "results" => [itunes_song_result] }
    resp = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("creep")
      track = results.first
      assert_equal "Creep",       track[:title]
      assert_equal "Radiohead",   track[:artist]
      assert_equal "Pablo Honey", track[:album_title]
    end
  end

  test "search_tracks sets is_single: false for a regular album song" do
    body = { "results" => [itunes_song_result("collectionType" => "Album")] }
    resp = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("creep")
      assert_equal false, results.first[:is_single]
    end
  end

  test "search_tracks sets is_single: true when collectionType is Single" do
    body = { "results" => [itunes_song_result("collectionType" => "Single")] }
    resp = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("single track")
      assert_equal true, results.first[:is_single]
    end
  end

  test "search_tracks filters out results whose wrapperType is not 'track'" do
    non_track = itunes_song_result("wrapperType" => "collection")
    body      = { "results" => [itunes_song_result, non_track] }
    resp      = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("creep")
      assert_equal 1, results.size
    end
  end

  test "search_tracks filters out results whose kind is not 'song'" do
    non_song = itunes_song_result("kind" => "music-video")
    body     = { "results" => [itunes_song_result, non_song] }
    resp     = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("creep")
      assert_equal 1, results.size
    end
  end

  test "search_tracks returns [] when results array is empty" do
    body = { "results" => [] }
    resp = fake_response(success: true, body: body)

    stub_httparty(resp) do
      assert_equal [], service.search_tracks("nothing")
    end
  end

  # ---------------------------------------------------------------------------
  # search_tracks — HTTP error (5xx)
  # ---------------------------------------------------------------------------

  test "search_tracks returns [] on an HTTP 500 error" do
    resp = fake_response(success: false, body: nil, code: 500)

    stub_httparty(resp) do
      result = service.search_tracks("creep")
      assert_equal [], result
    end
  end

  test "search_tracks returns [] when HTTParty raises a StandardError" do
    stub_httparty(->(*_args) { raise StandardError, "connection refused" }) do
      result = service.search_tracks("creep")
      assert_equal [], result
    end
  end

  # ---------------------------------------------------------------------------
  # parse_track_result — is_single flag (via public interface)
  # ---------------------------------------------------------------------------

  test "parse_track_result marks is_single: true when collectionType is Single" do
    body = { "results" => [itunes_song_result("collectionType" => "Single")] }
    resp = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("any")
      assert results.first[:is_single], "expected is_single to be true for a Single"
    end
  end

  test "parse_track_result marks is_single: false when collectionType is Album" do
    body = { "results" => [itunes_song_result("collectionType" => "Album")] }
    resp = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("any")
      assert_not results.first[:is_single]
    end
  end

  test "parse_track_result returns nil (filtered out) when trackId is absent" do
    missing_id = itunes_song_result.tap { |r| r.delete("trackId") }
    body       = { "results" => [missing_id] }
    resp       = fake_response(success: true, body: body)

    stub_httparty(resp) do
      results = service.search_tracks("any")
      # compact in the service removes nils → result list is empty
      assert_equal [], results
    end
  end
end
