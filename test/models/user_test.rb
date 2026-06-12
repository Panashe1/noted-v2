require "test_helper"

class UserTest < ActiveSupport::TestCase
  # A real, valid 1x1 PNG so content-type identification passes; we only want to
  # exercise the size check in the oversize test.
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  # Unsaved user so attaching doesn't immediately persist/analyze — validations run
  # against the in-memory attachment.
  def build_user
    User.new(username: "avatartest", email: "av@test.dev", password: "password123")
  end

  test "accepts an avatar within the size limit" do
    user = build_user
    user.avatar.attach(io: StringIO.new(PNG), filename: "a.png", content_type: "image/png")
    assert user.valid?, user.errors.full_messages.inspect
  end

  test "rejects an avatar over the 5 MB size limit" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(PNG), filename: "big.png", content_type: "image/png"
    )
    # Pretend the (real, tiny) file is oversized — exercises the size cap without a 6 MB file.
    blob.update_column(:byte_size, User::MAX_AVATAR_SIZE + 1)

    user = build_user
    user.avatar.attach(blob)
    assert_not user.valid?
    assert user.errors[:avatar].any?, "expected an avatar size error"
  ensure
    blob&.purge
  end

  test "rejects a non-image avatar content type" do
    user = build_user
    user.avatar.attach(io: StringIO.new("nope"), filename: "a.txt", content_type: "text/plain")
    assert_not user.valid?
    assert user.errors[:avatar].any?
  end
end
