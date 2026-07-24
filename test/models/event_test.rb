require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "record writes a row" do
    assert_difference "Event.count", 1 do
      Event.record("run.started", subject: runs(:completed_run), user: users(:admin))
    end

    event = Event.recent.first
    assert_equal "run.started", event.action
    assert_equal runs(:completed_run), event.subject
    assert_equal users(:admin), event.user
  end

  test "record swallows a bad action instead of raising" do
    assert_no_difference "Event.count" do
      assert_nil Event.record("not.an.action", subject: runs(:completed_run))
    end
  end

  test "record swallows a missing subject instead of raising" do
    assert_no_difference "Event.count" do
      assert_nil Event.record("run.started", subject: nil)
    end
  end

  test "actor_label falls back to system" do
    event = Event.record("run.completed", subject: runs(:completed_run))
    assert_equal "system", event.actor_label
  end

  test "recent orders newest first" do
    older = Event.record("run.started", subject: runs(:completed_run))
    older.update!(created_at: 2.days.ago)
    newer = Event.record("run.completed", subject: runs(:completed_run))

    assert_equal [newer, older], Event.recent.limit(2).to_a
  end

  test "an event survives its subject being deleted" do
    run = runs(:todo_run)
    event = Event.record("run.completed", subject: run)
    run.destroy!

    assert_nil event.reload.subject
    assert_equal "run.completed", event.action
  end

  test "deleting a user keeps the event and nullifies the actor" do
    user = User.create!(email: "temp-event@test.com", password: "password12")
    event = Event.record("run.started", subject: runs(:completed_run), user: user)

    user.destroy!
    assert_equal "system", event.reload.actor_label
  end
end
