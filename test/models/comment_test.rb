require "test_helper"

class CommentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = users(:admin)
    @run = runs(:completed_run)
  end

  def comment_with(body, commentable: @run, user: @author)
    Comment.new(commentable: commentable, user: user, body: body)
  end

  test "requires a body" do
    assert_not comment_with("").valid?
  end

  test "rejects a commentable type outside the allowlist" do
    comment = Comment.new(user: @author, body: "x", commentable_type: "User", commentable_id: @author.id)
    assert_not comment.valid?
    assert_includes comment.errors[:commentable_type], "is not included in the list"
  end

  test "run resolves for a run, a run step, and not for a task" do
    assert_equal @run, comment_with("x").run
    assert_equal runs(:completed_run), comment_with("x", commentable: run_steps(:passed_step)).run
    assert_nil comment_with("x", commentable: pipeline_tasks(:ready_task)).run
  end

  # --- Mention extraction ---

  test "matches the whole local part of an email" do
    other = User.create!(email: "dana@test.com", password: "password12")
    assert_equal [other], comment_with("nice work @dana").mentioned_users
  end

  test "matches the first segment of a dotted local part" do
    other = User.create!(email: "rick.cagle@hey.com", password: "password12")
    assert_equal [other], comment_with("@rick can you look?").mentioned_users
  end

  test "matches underscore and hyphen separated local parts" do
    under = User.create!(email: "sam_smith@test.com", password: "password12")
    hyphen = User.create!(email: "lee-jones@test.com", password: "password12")

    assert_equal [under], comment_with("@sam ping").mentioned_users
    assert_equal [hyphen], comment_with("@lee ping").mentioned_users
  end

  test "does not match on a bare prefix" do
    User.create!(email: "dana@test.com", password: "password12")
    assert_empty comment_with("@dan is not dana").mentioned_users
  end

  test "ignores self-mentions" do
    local = @author.email.split("@").first
    assert_empty comment_with("note to self @#{local}").mentioned_users
  end

  test "handles several mentions and deduplicates" do
    a = User.create!(email: "aa@test.com", password: "password12")
    b = User.create!(email: "bb@test.com", password: "password12")
    found = comment_with("@aa @bb @aa").mentioned_users
    assert_equal [a, b].sort_by(&:id), found.sort_by(&:id)
  end

  test "returns nothing when there are no mention tokens" do
    User.create!(email: "dana@test.com", password: "password12")
    assert_empty comment_with("no mentions here").mentioned_users
  end

  # --- Mention notifications ---

  test "a mention enqueues a notification carrying the comment" do
    Setting["webhook_url"] = "https://example.test/hook"
    User.create!(email: "dana@test.com", password: "password12")

    assert_enqueued_jobs 1, only: NotifyJob do
      Comment.create!(commentable: @run, user: @author, body: "@dana take a look", anchor: "replay_step_9")
    end

    enqueued = enqueued_jobs.find { |j| j["job_class"] == "NotifyJob" }
    event, run_id, extra = enqueued["arguments"]
    assert_equal "comment.mentioned", event
    assert_equal @run.id, run_id
    assert_equal "dana@test.com", extra["comment"]["mentioned"]
    assert_equal "replay_step_9", extra["comment"]["anchor"]
  end

  test "no notification is enqueued without a destination configured" do
    User.create!(email: "dana@test.com", password: "password12")
    assert_no_enqueued_jobs only: NotifyJob do
      Comment.create!(commentable: @run, user: @author, body: "@dana take a look")
    end
  end

  test "a task comment mention enqueues nothing since it has no run" do
    Setting["webhook_url"] = "https://example.test/hook"
    User.create!(email: "dana@test.com", password: "password12")

    assert_no_enqueued_jobs only: NotifyJob do
      Comment.create!(commentable: pipeline_tasks(:ready_task), user: @author, body: "@dana look")
    end
  end

  test "destroying a run destroys its comments" do
    run = runs(:todo_run)
    run.comments.create!(user: @author, body: "bye")
    assert_difference "Comment.count", -1 do
      run.destroy!
    end
  end
end
