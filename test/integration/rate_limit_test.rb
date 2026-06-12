require "test_helper"

class RateLimitTest < ActionDispatch::IntegrationTest
  setup do
    @original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  teardown do
    Rack::Attack.cache.store = @original_store
    Rack::Attack.reset!
  end

  test "login is throttled after exceeding the per-IP limit" do
    # limit is 10/min; the 11th attempt should be blocked.
    10.times do
      post "/users/sign_in", params: { user: { email: "nobody@test.dev", password: "wrong" } }
      assert_not_equal 429, response.status, "should not be throttled within the limit"
    end
    post "/users/sign_in", params: { user: { email: "nobody@test.dev", password: "wrong" } }
    assert_response :too_many_requests
    assert response.headers["Retry-After"].present?, "expected a Retry-After header"
  end

  test "normal browsing is not throttled" do
    get "/users/sign_in"
    assert_response :success
  end
end
