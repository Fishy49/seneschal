require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  test "valid workflow" do
    w = Workflow.new(name: "New Workflow", project: projects(:seneschal))
    assert w.valid?
  end

  test "requires name" do
    w = Workflow.new(project: projects(:seneschal))
    assert_not w.valid?
    assert_includes w.errors[:name], "can't be blank"
  end

  test "requires unique name per project" do
    w = Workflow.new(
      name: workflows(:deploy).name,
      project: projects(:seneschal)
    )
    assert_not w.valid?
  end

  test "allows same name in different projects" do
    w = Workflow.new(
      name: workflows(:deploy).name,
      project: projects(:other_project)
    )
    assert w.valid?
  end

  test "has_many steps ordered by position" do
    workflow = workflows(:deploy)
    positions = workflow.steps.pluck(:position)
    assert_equal positions.sort, positions
  end

  test "destroying workflow destroys steps" do
    workflow = projects(:other_project).workflows.create!(name: "Disposable")
    workflow.steps.create!(name: "s1", step_type: "command", body: "echo 1", position: 1)
    workflow.steps.create!(name: "s2", step_type: "command", body: "echo 2", position: 2)
    assert_difference "Step.count", -2 do
      workflow.destroy
    end
  end

  # Cost lives inside the run step's stream_log result entry, so a run only
  # reports a cost when one of its steps carries that payload.
  def finished_run(workflow, status, cost: nil)
    run = workflow.runs.create!(status: status, context: {}, input: {})
    if cost
      log = [{ "type" => "result", "total_cost_usd" => cost, "usage" => {} }]
      run.run_steps.create!(step: workflow.steps.first, status: "passed", attempt: 1, stream_log: log)
    end
    run
  end

  test "stats reports nothing useful for a workflow nobody has run" do
    workflow = projects(:seneschal).workflows.create!(name: "Untouched")
    stats = workflow.stats

    assert_equal 0, stats.run_count
    assert_nil stats.success_rate
    assert_nil stats.median_cost
  end

  test "stats counts every run but rates only the finished ones" do
    workflow = workflows(:deploy)
    workflow.runs.destroy_all
    finished_run(workflow, "completed")
    finished_run(workflow, "failed")
    workflow.runs.create!(status: "running", context: {}, input: {})

    stats = workflow.stats
    assert_equal 3, stats.run_count
    assert_in_delta 0.5, stats.success_rate
  end

  test "stats reports a full success rate when everything passed" do
    workflow = workflows(:deploy)
    workflow.runs.destroy_all
    2.times { finished_run(workflow, "completed") }

    assert_in_delta 1.0, workflow.stats.success_rate
  end

  test "stats takes the median cost of completed runs and ignores costless ones" do
    workflow = workflows(:deploy)
    workflow.runs.destroy_all
    finished_run(workflow, "completed", cost: 1.0)
    finished_run(workflow, "completed", cost: 3.0)
    finished_run(workflow, "completed", cost: 9.0)
    finished_run(workflow, "completed")
    finished_run(workflow, "failed", cost: 100.0)

    assert_in_delta 3.0, workflow.stats.median_cost
  end

  test "stats averages the middle pair for an even number of costs" do
    workflow = workflows(:deploy)
    workflow.runs.destroy_all
    finished_run(workflow, "completed", cost: 2.0)
    finished_run(workflow, "completed", cost: 4.0)

    assert_in_delta 3.0, workflow.stats.median_cost
  end

  test "stats rates only the most recent sample of finished runs" do
    workflow = workflows(:deploy)
    workflow.runs.destroy_all
    (Workflow::STATS_SAMPLE + 5).times { finished_run(workflow, "completed") }
    finished_run(workflow, "failed")

    stats = workflow.stats
    assert_equal Workflow::STATS_SAMPLE + 6, stats.run_count
    assert_in_delta (Workflow::STATS_SAMPLE - 1) / Workflow::STATS_SAMPLE.to_f, stats.success_rate
  end
end
