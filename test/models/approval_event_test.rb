require "test_helper"
require "turbo/broadcastable/test_helper"

class ApprovalEventTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @run_step = run_steps(:awaiting_step_run_step)
  end

  test "requires a known action" do
    event = ApprovalEvent.new(run_step: @run_step, action: "shrugged")
    assert_not event.valid?
    assert_includes event.errors[:action], "is not included in the list"
  end

  test "accepts approved and rejected" do
    ApprovalEvent::ACTIONS.each do |action|
      assert ApprovalEvent.new(run_step: @run_step, action: action).valid?
    end
  end

  test "actor_label falls back to system for an unattributed event" do
    event = ApprovalEvent.new(run_step: @run_step, action: "approved")
    assert_equal "system", event.actor_label
  end

  test "recent orders newest first" do
    older = @run_step.approval_events.create!(action: "rejected", created_at: 2.hours.ago)
    newer = @run_step.approval_events.create!(action: "approved", created_at: 1.minute.ago)
    assert_equal [newer, older], @run_step.approval_events.recent.to_a
  end

  test "deleting a user keeps the event and nullifies the actor" do
    user = User.create!(email: "temp-approver@test.com", password: "password12")
    event = @run_step.approval_events.create!(action: "approved", user: user)

    user.destroy!
    assert ApprovalEvent.exists?(event.id)
    assert_equal "system", event.reload.actor_label
  end

  test "destroying the run step destroys its events" do
    @run_step.approval_events.create!(action: "approved")
    assert_difference "ApprovalEvent.count", -1 do
      @run_step.destroy!
    end
  end
  test "a seal broadcasts into its run's thread" do
    assert_enqueued_jobs 1, only: Turbo::Streams::ActionBroadcastJob do
      @run_step.approval_events.create!(user: users(:admin), action: "approved")
    end
  end
  test "the broadcast job renders the seal partial with its comment" do
    seal = nil
    streams = capture_turbo_stream_broadcasts(@run_step.run) do
      perform_enqueued_jobs do
        seal = @run_step.approval_events.create!(user: users(:admin), action: "approved",
                                                 comment: "index handled")
      end
    end

    stream = streams.find { |s| s["target"] == "run_discussion" }
    assert stream, "expected an append targeting run_discussion"
    assert_includes stream.to_html, "approval_event_#{seal.id}"
    assert_includes stream.to_html, "sealed"
    assert_includes stream.to_html, "index handled"
  end
end
