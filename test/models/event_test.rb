require "test_helper"
require "turbo/broadcastable/test_helper"

class EventTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

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

  test "awaiting and token-wait transitions are recordable actions" do
    assert Event.record("run.awaiting_approval", subject: runs(:awaiting_run))
    assert Event.record("run.waiting_for_tokens", subject: runs(:completed_run))
    assert Event.record("run.resumed", subject: runs(:completed_run))
  end

  test "a run-level event broadcasts into the run thread" do
    assert_enqueued_jobs 1, only: Turbo::Streams::ActionBroadcastJob do
      Event.record("run.started", subject: runs(:completed_run), user: users(:admin))
    end
  end

  test "thread-hidden and non-run events do not broadcast" do
    assert_no_enqueued_jobs only: Turbo::Streams::ActionBroadcastJob do
      Event.record("run.approved", subject: runs(:completed_run), user: users(:admin))
      Event.record("workflow.updated", subject: workflows(:deploy), user: users(:admin))
    end
  end

  test "the broadcast job renders the event partial into the run stream" do
    run = runs(:completed_run)
    event = nil
    streams = capture_turbo_stream_broadcasts(run) do
      perform_enqueued_jobs do
        event = Event.record("run.started", subject: run, user: users(:admin))
      end
    end

    stream = streams.find { |s| s["target"] == "run_discussion" }
    assert stream, "expected an append targeting run_discussion"
    assert_equal "append", stream["action"]
    assert_includes stream.to_html, "event_#{event.id}"
    assert_includes stream.to_html, "started this run"
  end

  test "run_thread scope keeps the story and hides the duplicates" do
    run = runs(:completed_run)
    kept = Event.record("run.started", subject: run)
    hidden = Event.record("run.approved", subject: run)

    threaded = Event.run_thread(run)
    assert_includes threaded, kept
    assert_not_includes threaded, hidden
  end
end
