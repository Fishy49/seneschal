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

  # The presence roster itself cannot be asserted here: config/cable.yml uses
  # the `test` adapter, which collects broadcasts for assert_broadcast_on but
  # never delivers them to a real websocket client. RunPresence and
  # PresenceChannel carry the behavioral coverage; this only proves the strip
  # renders and its controller loads without error.
  test "the run page mounts the presence strip" do
    visit run_path(runs(:completed_run))
    assert_selector "[data-controller='presence']", visible: :all
    assert_selector "[data-presence-target='roster']", visible: :all
  end

  test "the run header summarises cost and tokens" do
    visit run_path(runs(:completed_run))
    assert_text "$0.05"
    assert_text "24.0k tokens"
  end

  test "the full metrics breakdown lives on the transcript" do
    visit replay_run_path(runs(:completed_run))
    assert_text(/turns/i)
    assert_text "5 turns"
  end

  test "filter runs by status" do
    visit runs_path
    select "Failed", from: "status"

    assert_text "Deploy Pipeline"
  end

  # --- unified discussion ---

  test "posting a comment appends to the feed without collapsing open steps" do
    run = runs(:completed_run)
    step = run.run_steps.first
    visit run_path(run)

    # Expand a step first; a full page reload would close it again, so it
    # staying open is the proof the comment went over a stream.
    find("#run_step_#{step.id} summary", match: :first).click
    assert_selector "#run_step_#{step.id} details[data-preserve-key='step'][open]"

    fill_in "comment[body]", with: "Streamed, not reloaded."
    click_button "Comment", exact: true

    within "#run_discussion" do
      assert_text "Streamed, not reloaded."
    end
    assert_no_text "Nothing yet."
    assert_selector "#run_step_#{step.id} details[data-preserve-key='step'][open]"
  end

  test "comment on this step preselects the step and chips the comment" do
    run = runs(:completed_run)
    step = run.run_steps.first
    visit run_path(run)

    find("#run_step_#{step.id} summary", match: :first).click
    within "#run_step_#{step.id}" do
      click_button "Comment on this step"
    end
    assert_equal "RunStep:#{step.id}", find("select[name='commentable']").value

    fill_in "comment[body]", with: "About this step specifically."
    click_button "Comment", exact: true

    within "#run_discussion" do
      assert_text "About this step specifically."
      assert_selector "a[href='#run_step_#{step.id}']", text: step.step.name
    end
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

  test "filter chip state round-trips through the URL" do
    visit replay_run_path(runs(:completed_run))
    assert_no_match(/show=/, current_url)

    check_chip("System")
    assert_match(/show=[^&]*system/, current_url)

    # A fresh load of the copied URL restores the same chips.
    visit current_url
    assert_text "claude-sonnet-4-20250514"

    uncheck_chip("System")
    assert_no_match(/show=/, current_url)
  end

  test "a step permalink lands on the highlighted step" do
    run_step = runs(:completed_run).run_steps.first
    visit "#{replay_run_path(runs(:completed_run))}#replay_step_#{run_step.id}"

    assert_selector "#replay_step_#{run_step.id}:target"
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
