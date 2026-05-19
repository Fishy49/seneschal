require "application_system_test_case"

class RunsTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
  end

  test "list runs" do
    visit runs_path
    assert_text "Deploy Pipeline"
    assert_text "Seneschal"
  end

  test "view run details" do
    visit run_path(runs(:completed_run))
    assert_text "Run ##{runs(:completed_run).id}"
    assert_text "Plan Feature"
  end

  test "view run with usage stats" do
    visit run_path(runs(:completed_run))
    assert_text "$0.05"
    assert_text "5 turns"
  end

  test "filter runs by status" do
    visit runs_path
    select "Failed", from: "status"

    assert_text "Deploy Pipeline"
  end

  # --- R10: trajectory replay + diff ---

  test "replay timeline filter chip hides matching entries" do
    visit replay_run_path(runs(:completed_run))
    # Default chips render. System is off by default, so its content is
    # hidden — flip it on to confirm reveal, then off to confirm hide.
    check_chip("System")
    assert_text "claude-sonnet-4-20250514"
    uncheck_chip("System")
    assert_no_text "claude-sonnet-4-20250514"
  end

  test "compare view picks a default target and renders side-by-side" do
    # Seed a second run on the same task so the compare picker has a target.
    other = Run.create!(workflow: workflows(:deploy),
                        pipeline_task: pipeline_tasks(:completed_task),
                        status: "completed", started_at: 1.day.ago,
                        finished_at: 23.hours.ago, context: {}, input: {})

    visit diff_run_path(runs(:completed_run))
    assert_text "Compare"
    assert_text "Run ##{other.id}"
  end

  private

  def check_chip(label)
    find("label", text: label).find("input").check
  end

  def uncheck_chip(label)
    find("label", text: label).find("input").uncheck
  end
end
