require "test_helper"

class ComponentsHelperTest < ActionView::TestCase
  test "avatar_for renders initials from a dotted email local part" do
    html = avatar_for(users(:admin))
    assert_includes html, users(:admin).email
    assert_includes html, user_initials(users(:admin).email)
  end

  test "avatar_for uses the email as the tooltip" do
    assert_includes avatar_for(users(:other)), "title=\"#{users(:other).email}\""
  end

  test "avatar_for renders nothing for a nil user" do
    assert_nil avatar_for(nil)
  end

  test "avatar_for honours the size local" do
    assert_includes avatar_for(users(:admin), size: :md), AVATAR_SIZES[:md]
  end

  test "avatar_for falls back to the small size for an unknown size" do
    assert_includes avatar_for(users(:admin), size: :enormous), AVATAR_SIZES[:sm]
  end

  test "user_initials splits on separators" do
    assert_equal "JD", user_initials("john.doe@example.com")
    assert_equal "AB", user_initials("a_b@example.com")
  end

  test "user_initials takes the first two letters of a single-word local part" do
    assert_equal "AD", user_initials("admin@example.com")
  end

  test "status_dot maps running to info and pulses" do
    html = status_dot("running")
    assert_includes html, "bg-info"
    assert_includes html, "animate-pulse"
  end

  test "status_dot maps completed and passed to success" do
    assert_includes status_dot("completed"), "bg-success"
    assert_includes status_dot("passed"), "bg-success"
  end

  test "status_dot maps failed to danger" do
    assert_includes status_dot("failed"), "bg-danger"
  end

  test "status_dot maps approval and token waits to brass" do
    assert_includes status_dot("awaiting_approval"), "bg-brass"
    assert_includes status_dot("waiting_for_tokens"), "bg-brass"
  end

  test "status_dot falls back to muted" do
    html = status_dot("pending")
    assert_includes html, "bg-content-muted"
    assert_not_includes html, "animate-pulse"
  end

  test "status_dot titles the status in plain words" do
    assert_includes status_dot("awaiting_approval"), "title=\"awaiting approval\""
  end

  test "chip_tone_classes falls back to neutral" do
    assert_equal CHIP_TONES[:neutral], chip_tone_classes(:nonsense)
    assert_equal CHIP_TONES[:danger], chip_tone_classes(:danger)
  end
end
