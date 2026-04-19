require "test_helper"

class PipelineTaskTest < ActiveSupport::TestCase
  test "valid task" do
    t = PipelineTask.new(
      title: "New Task", body: "Do something",
      kind: "feature", status: "draft",
      project: projects(:seneschal)
    )
    assert t.valid?
  end

  test "requires title" do
    t = PipelineTask.new(body: "x", project: projects(:seneschal))
    assert_not t.valid?
    assert_includes t.errors[:title], "can't be blank"
  end

  test "requires body" do
    t = PipelineTask.new(title: "x", project: projects(:seneschal))
    assert_not t.valid?
    assert_includes t.errors[:body], "can't be blank"
  end

  test "validates kind inclusion" do
    t = PipelineTask.new(title: "x", body: "x", project: projects(:seneschal), kind: "invalid")
    assert_not t.valid?
  end

  test "validates status inclusion" do
    t = PipelineTask.new(title: "x", body: "x", project: projects(:seneschal), status: "invalid")
    assert_not t.valid?
  end

  test "non-draft requires workflow" do
    t = PipelineTask.new(
      title: "x", body: "x", kind: "feature",
      status: "ready", project: projects(:seneschal)
    )
    assert_not t.valid?
    assert_includes t.errors[:workflow], "can't be blank"
  end

  test "draft does not require workflow" do
    t = PipelineTask.new(
      title: "x", body: "x", kind: "feature",
      status: "draft", project: projects(:seneschal)
    )
    assert t.valid?
  end

  test "executable? when ready with workflow" do
    assert pipeline_tasks(:ready_task).executable?
  end

  test "not executable? when draft" do
    assert_not pipeline_tasks(:draft_task).executable?
  end

  test "latest_run returns most recent run" do
    task = pipeline_tasks(:running_task)
    assert_equal runs(:active_run), task.latest_run
  end

  test "recent scope applies ordering" do
    tasks = PipelineTask.recent
    assert tasks.any?
    assert_equal "updated_at", tasks.order_values.first.expr.name
  end

  test "actionable scope returns draft and ready tasks" do
    actionable = PipelineTask.actionable
    actionable.each do |t|
      assert_includes ["draft", "ready"], t.status
    end
  end

  test "usage_stats aggregates across runs" do
    task = pipeline_tasks(:completed_task)
    stats = task.usage_stats
    assert_not_nil stats
    assert stats[:cost_usd].positive?
    assert stats[:input_tokens].positive?
  end

  test "defaults to manual trigger" do
    t = PipelineTask.create!(
      title: "m", body: "m", kind: "feature", status: "draft",
      project: projects(:seneschal)
    )
    assert_equal "manual", t.trigger_type
    assert t.manual?
  end

  test "cron trigger requires a valid expression" do
    t = pipeline_tasks(:ready_task)
    t.trigger_type = "cron"
    t.trigger_config = { "cron" => "not a cron" }
    assert_not t.valid?
    assert_includes t.errors[:trigger_config].join, "invalid cron"

    t.trigger_config = { "cron" => "0 9 * * 1-5" }
    assert t.valid?
  end

  test "cron trigger rejects blank expression" do
    t = pipeline_tasks(:ready_task)
    t.trigger_type = "cron"
    t.trigger_config = {}
    assert_not t.valid?
    assert_includes t.errors[:trigger_config].join, "cron expression"
  end

  test "github_watch requires repo url and branch" do
    t = pipeline_tasks(:ready_task)
    t.trigger_type = "github_watch"
    t.trigger_config = {}
    assert_not t.valid?

    t.trigger_config = { "repo_url" => "git@github.com:a/b.git", "branch" => "main" }
    assert t.valid?
  end

  test "record_cron_fire! persists iso8601 timestamp" do
    t = pipeline_tasks(:ready_task)
    t.update!(trigger_type: "cron", trigger_config: { "cron" => "0 * * * *" })
    fired = Time.zone.parse("2025-01-02 03:00:00")
    t.record_cron_fire!(fired)
    assert_equal fired, t.reload.last_fired_at
  end

  test "record_seen_sha! persists sha" do
    t = pipeline_tasks(:ready_task)
    t.update!(trigger_type: "github_watch",
              trigger_config: { "repo_url" => "git@github.com:a/b.git", "branch" => "main" })
    t.record_seen_sha!("deadbeef")
    assert_equal "deadbeef", t.reload.last_seen_sha
  end
end
