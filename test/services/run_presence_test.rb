require "test_helper"

class RunPresenceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @presence = RunPresence.new(1)
  end

  test "starts empty" do
    assert_empty @presence.viewers
  end

  test "join adds a viewer and returns the roster" do
    assert_equal ["a@test.com"], @presence.join("a@test.com")
    assert_equal ["a@test.com"], @presence.viewers
  end

  test "viewers are sorted and deduplicated" do
    @presence.join("b@test.com")
    @presence.join("a@test.com")
    @presence.join("a@test.com")
    assert_equal ["a@test.com", "b@test.com"], @presence.viewers
  end

  test "a second tab keeps the person present until both leave" do
    @presence.join("a@test.com")
    @presence.join("a@test.com")

    @presence.leave("a@test.com")
    assert_equal ["a@test.com"], @presence.viewers, "closing one tab must not evict the person"

    @presence.leave("a@test.com")
    assert_empty @presence.viewers
  end

  test "leaving without joining does not push the count negative" do
    @presence.leave("ghost@test.com")
    assert_empty @presence.viewers

    @presence.join("ghost@test.com")
    assert_equal ["ghost@test.com"], @presence.viewers
  end

  test "rosters are scoped per run" do
    RunPresence.new(1).join("a@test.com")
    assert_empty RunPresence.new(2).viewers
  end
end
