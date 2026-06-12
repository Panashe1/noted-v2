require "test_helper"

class AlbumTest < ActiveSupport::TestCase
  def album_with(url)
    Album.new(title: "T", artist: "A", apple_music_url: url)
  end

  test "apple_music_link returns https URLs" do
    url = "https://music.apple.com/us/album/ok-computer/123"
    assert_equal url, album_with(url).apple_music_link
  end

  test "apple_music_link returns http URLs" do
    url = "http://example.com/x"
    assert_equal url, album_with(url).apple_music_link
  end

  test "apple_music_link rejects javascript: scheme (XSS guard)" do
    assert_nil album_with("javascript:alert(document.cookie)").apple_music_link
  end

  test "apple_music_link rejects data: scheme" do
    assert_nil album_with("data:text/html,<script>alert(1)</script>").apple_music_link
  end

  test "apple_music_link returns nil for blank or malformed values" do
    assert_nil album_with(nil).apple_music_link
    assert_nil album_with("").apple_music_link
    assert_nil album_with("ht!tp://%%%bad").apple_music_link
  end
end
