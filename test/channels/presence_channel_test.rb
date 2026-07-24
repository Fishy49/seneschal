require "test_helper"

class PresenceChannelTest < ActionCable::Channel::TestCase
  setup do
    Rails.cache.clear
    @run = runs(:active_run)
    stub_connection current_user: users(:admin)
  end

  def presence = RunPresence.new(@run.id)

  test "subscribing streams the run's presence channel and joins the roster" do
    subscribe(run_id: @run.id)

    assert subscription.confirmed?
    assert_has_stream "presence:run:#{@run.id}"
    assert_equal [users(:admin).email], presence.viewers
  end

  test "subscribing broadcasts the roster" do
    assert_broadcast_on("presence:run:#{@run.id}", viewers: [users(:admin).email]) do
      subscribe(run_id: @run.id)
    end
  end

  test "unsubscribing removes the viewer and broadcasts the empty roster" do
    subscribe(run_id: @run.id)

    assert_broadcast_on("presence:run:#{@run.id}", viewers: []) do
      unsubscribe
    end
    assert_empty presence.viewers
  end

  test "another viewer already present stays in the roster after this one leaves" do
    presence.join("someone.else@test.com")
    subscribe(run_id: @run.id)

    assert_broadcast_on("presence:run:#{@run.id}", viewers: ["someone.else@test.com"]) do
      unsubscribe
    end
  end

  test "subscribing to an unknown run is rejected" do
    subscribe(run_id: -1)
    assert subscription.rejected?
  end
end
