require "test_helper"

class I18nRenderTest < ActionDispatch::IntegrationTest
  setup do
    @user  = users(:alice)
    @album = albums(:ok_computer)
    @listen_log = ListenLog.create!(user: @user, album: @album, rating: 8, listened_on: Date.yesterday)
    @track_log  = track_logs(:alice_paranoid_android)
    sign_in @user
  end

  def assert_renders(path)
    [nil, "es"].each do |loc|
      full = "#{loc ? "/#{loc}" : ""}#{path}"
      get full
      assert_response :success, "expected 200 for #{full}"
    end
  end

  test "discover idle renders both locales" do
    assert_renders "/discover"
  end

  test "discover with query renders both locales" do
    stub_instance_method(ClaudeService, :recommend, "[]") do
      assert_renders "/discover?q=jazz"
    end
  end

  test "listen log edit renders both locales" do
    assert_renders "/listen_logs/#{@listen_log.id}/edit"
  end

  test "track log edit renders both locales" do
    assert_renders "/track_logs/#{@track_log.id}/edit"
  end

  test "music search no-results renders both locales" do
    stub_instance_method(MusicSearchService, :search_albums, []) do
      assert_renders "/music/search?q=zzx"
    end
  end

  test "es discover shows Spanish copy" do
    get "/es/discover"
    assert_match "Descubrir",          response.body
    assert_match "Preguntar a Claude", response.body
  end

  test "es listen log edit shows Spanish copy" do
    get "/es/listen_logs/#{@listen_log.id}/edit"
    assert_match "Guardar cambios", response.body
    assert_match "Cancelar",        response.body
  end

  test "es music search shows Spanish no-results" do
    stub_instance_method(MusicSearchService, :search_albums, []) do
      get "/es/music/search?q=zzx"
    end
    assert_match "No se encontraron álbumes", response.body
  end
end
