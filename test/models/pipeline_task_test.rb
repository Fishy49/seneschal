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
end
