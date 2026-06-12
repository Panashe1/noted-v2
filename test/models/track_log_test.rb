require "test_helper"

class TrackLogTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------
  # alice already has a log for :paranoid_android (see fixtures/track_logs.yml)

  def setup
    @alice = users(:alice)
    @bob   = users(:bob)
    @track = tracks(:karma_police)       # not yet logged by anyone
  end

  # ---------------------------------------------------------------------------
  # Presence validation — listened_on
  # ---------------------------------------------------------------------------

  test "is valid with required attributes" do
    log = TrackLog.new(
      user:        @alice,
      track:       @track,
      listened_on: Date.current,
      rating:      nil
    )
    assert log.valid?, log.errors.full_messages.inspect
  end

  test "is invalid without listened_on" do
    log = TrackLog.new(user: @alice, track: @track, listened_on: nil)
    assert_not log.valid?
    assert_includes log.errors[:listened_on], "can't be blank"
  end

  # ---------------------------------------------------------------------------
  # Rating validation — must be 1..10 integer or nil
  # ---------------------------------------------------------------------------

  test "is valid with a rating of 1" do
    log = TrackLog.new(user: @alice, track: @track, listened_on: Date.current, rating: 1)
    assert log.valid?
  end

  test "is valid with a rating of 10" do
    log = TrackLog.new(user: @alice, track: @track, listened_on: Date.current, rating: 10)
    assert log.valid?
  end

  test "is valid when rating is nil" do
    log = TrackLog.new(user: @alice, track: @track, listened_on: Date.current, rating: nil)
    assert log.valid?
  end

  test "is invalid with a rating of 0" do
    log = TrackLog.new(user: @alice, track: @track, listened_on: Date.current, rating: 0)
    assert_not log.valid?
    assert log.errors[:rating].any?
  end

  test "is invalid with a rating of 11" do
    log = TrackLog.new(user: @alice, track: @track, listened_on: Date.current, rating: 11)
    assert_not log.valid?
    assert log.errors[:rating].any?
  end

  test "is invalid with a non-integer rating" do
    log = TrackLog.new(user: @alice, track: @track, listened_on: Date.current, rating: 7.5)
    assert_not log.valid?
    assert log.errors[:rating].any?
  end

  # ---------------------------------------------------------------------------
  # Uniqueness — same user cannot log the same track twice
  # ---------------------------------------------------------------------------

  test "is invalid when user has already logged the same track" do
    # alice already has a fixture log for :paranoid_android
    duplicate = TrackLog.new(
      user:        @alice,
      track:       tracks(:paranoid_android),
      listened_on: Date.current
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:user_id].any?,
           "expected user_id uniqueness error, got: #{duplicate.errors.full_messages}"
  end

  test "is valid when a different user logs the same track" do
    log = TrackLog.new(
      user:        @bob,
      track:       tracks(:paranoid_android),   # alice's track, not bob's
      listened_on: Date.current
    )
    assert log.valid?, log.errors.full_messages.inspect
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  test "belongs to a user" do
    assert_respond_to TrackLog.new, :user
  end

  test "belongs to a track" do
    assert_respond_to TrackLog.new, :track
  end

  test "is invalid without a user" do
    log = TrackLog.new(track: @track, listened_on: Date.current)
    assert_not log.valid?
    assert log.errors[:user].any?
  end

  test "is invalid without a track" do
    log = TrackLog.new(user: @alice, listened_on: Date.current)
    assert_not log.valid?
    assert log.errors[:track].any?
  end

  # ---------------------------------------------------------------------------
  # No after_create taste-profile side effect
  # ---------------------------------------------------------------------------

  test "TrackLog has no after_create callback that triggers taste profile regeneration" do
    # ListenLog has an after_create that calls regenerate_taste_profile!
    # TrackLog must NOT — track logs are intentionally isolated from the taste system.
    taste_callbacks = TrackLog._create_callbacks.map(&:filter).map(&:to_s)
    assert_not taste_callbacks.any? { |c| c.include?("taste_profile") },
      "Expected no taste_profile callback on TrackLog, found: #{taste_callbacks.inspect}"
  end
end
