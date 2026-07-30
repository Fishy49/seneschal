require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "a failed run notifies its participants, minus whoever failed it" do
    run = runs(:completed_run)
    run.update!(started_by: users(:admin))
    run.comments.create!(user: users(:other), body: "watching this one")

    assert_difference "Notification.count", 1 do
      Event.record("run.failed", subject: run, user: users(:admin))
    end

    note = Notification.last
    assert_equal users(:other), note.user
    assert_equal "failed", note.reason
    assert_equal run, note.context
    assert_nil note.read_at
  end

  test "a comment notifies thread participants as replies" do
    run = runs(:completed_run)
    run.update!(started_by: users(:other))

    run.comments.create!(user: users(:admin), body: "no mention here")

    note = Notification.find_by(user: users(:other))
    assert note, "expected the run starter to be notified"
    assert_equal "reply", note.reason
    assert_equal run, note.context
  end

  test "a mention outranks a plain reply for the same person" do
    run = runs(:completed_run)
    run.update!(started_by: users(:other))

    run.comments.create!(user: users(:admin), body: "@other look at this")

    notes = Notification.where(user: users(:other))
    assert_equal 1, notes.count
    assert_equal "mention", notes.first.reason
  end

  test "task comment mentions are no longer dropped" do
    task = pipeline_tasks(:draft_task)

    task.comments.create!(user: users(:admin), body: "@other can you pick a workflow?")

    note = Notification.find_by(user: users(:other))
    assert note
    assert_equal "mention", note.reason
    assert_equal task, note.context
  end

  test "non-fanout actions write no notifications" do
    assert_no_difference "Notification.count" do
      Event.record("workflow.updated", subject: workflows(:deploy), user: users(:admin))
      Event.record("run.completed", subject: runs(:completed_run), user: users(:admin))
    end
  end

  test "mark_read settles a context" do
    run = runs(:completed_run)
    run.update!(started_by: users(:other))
    run.comments.create!(user: users(:admin), body: "hello")

    assert_equal 1, users(:other).notifications.unread.count
    Notification.mark_read(users(:other), run)
    assert_equal 0, users(:other).notifications.unread.count
  end
end
