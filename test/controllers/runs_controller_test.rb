require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists runs" do
    get runs_path
    assert_response :success
  end

  test "GET index filters by status" do
    get runs_path, params: { status: "running" }
    assert_response :success
  end

  test "GET show displays run" do
    get run_path(runs(:completed_run))
    assert_response :success
  end

  test "GET show offers a one-click re-run on a finished run" do
    run = runs(:completed_run)
    get run_path(run)
    assert_response :success
    assert_select "form[action=?]", execute_pipeline_task_path(run.pipeline_task)
  end

  test "GET show has no re-run button on a run without a task" do
    get run_path(runs(:todo_run))
    assert_response :success
    assert_select "form[action*=?]", "/execute", false
  end

  test "POST stop records who stopped the run" do
    run = runs(:active_run)
    post stop_run_path(run)
    run.reload
    assert_equal users(:admin), run.stopped_by
    assert_equal "Stopped by #{users(:admin).email}", run.error_message
  end

  test "POST stop marks run as stopped" do
    run = runs(:active_run)
    post stop_run_path(run)
    assert_redirected_to run_path(run)
    run.reload
    assert_equal "stopped", run.status
    assert_not_nil run.finished_at
  end

  test "POST stop updates task status to failed" do
    run = runs(:active_run)
    task = run.pipeline_task
    post stop_run_path(run)
    assert_equal "failed", task.reload.status
  end

  test "POST stop rejects non-active run" do
    post stop_run_path(runs(:completed_run))
    assert_redirected_to run_path(runs(:completed_run))
    assert_equal "completed", runs(:completed_run).reload.status
  end

  test "POST resume enqueues job for failed run" do
    run = runs(:failed_run)
    assert_enqueued_with(job: ExecuteRunJob) do
      post resume_run_path(run)
    end
    assert_redirected_to run_path(run)
  end

  test "POST resume rejects running run" do
    post resume_run_path(runs(:active_run))
    assert_redirected_to run_path(runs(:active_run))
  end

  test "POST retry_from creates new run" do
    run = runs(:failed_run)
    step = steps(:command_step)
    assert_difference "Run.count", 1 do
      assert_enqueued_with(job: ExecuteRunJob) do
        post retry_from_run_path(run), params: { step_id: step.id }
      end
    end
  end

  test "GET run show renders danger badge for skip_permissions project" do
    projects(:seneschal).update!(skip_permissions: true)
    run = workflows(:deploy).runs.create!(status: "running", context: {})
    get run_path(run)
    assert_response :success
    assert_match(/Danger mode/, response.body)
  end

  test "GET runs index shows danger indicator next to runs" do
    projects(:seneschal).update!(skip_permissions: true)
    workflows(:deploy).runs.create!(status: "running", context: {})
    get runs_path
    assert_response :success
    assert_match(/Danger mode/, response.body)
  end

  test "GET show renders awaiting_approval badge and approve/reject actions" do
    run = runs(:awaiting_run)
    run_steps(:awaiting_step_run_step)
    get run_path(run)
    assert_response :success
    assert_match(/awaiting approval/i, response.body)
    assert_select "form[action=?]", approve_run_path(run)
    assert_select "form[action=?]", reject_run_path(run)
  end

  test "POST approve marks run_step passed and enqueues after_approval job" do
    run = runs(:awaiting_run)
    rs = run_steps(:awaiting_step_run_step)
    assert_enqueued_with(job: ExecuteRunJob, args: [run, rs.step_id, { after_approval: true }]) do
      post approve_run_path(run)
    end
    assert_redirected_to run_path(run)
    assert_equal "passed", rs.reload.status
    assert_equal "running", run.reload.status
  end

  test "POST approve rejects non-awaiting_approval run" do
    post approve_run_path(runs(:active_run))
    assert_redirected_to run_path(runs(:active_run))
    assert_equal "running", runs(:active_run).reload.status
  end

  test "POST reject saves rejection_context and enqueues resume job" do
    run = runs(:awaiting_run)
    rs = run_steps(:awaiting_step_run_step)
    assert_enqueued_with(job: ExecuteRunJob, args: [run, rs.step_id, { resume: true }]) do
      post reject_run_path(run), params: { rejection_context: "Use a different branch name." }
    end
    assert_redirected_to run_path(run)
    assert_equal "Use a different branch name.", rs.reload.rejection_context
    assert_equal "awaiting_approval", rs.reload.status
    assert_equal "running", run.reload.status
  end

  test "POST reject rejects non-awaiting_approval run" do
    post reject_run_path(runs(:active_run)), params: { rejection_context: "nope" }
    assert_redirected_to run_path(runs(:active_run))
  end

  test "POST stop records a run.stopped event" do
    post stop_run_path(runs(:active_run))
    assert_equal "run.stopped", Event.recent.first.action
    assert_equal users(:admin), Event.recent.first.user
  end

  test "POST approve records a run.approved event naming the step" do
    post approve_run_path(runs(:awaiting_run))
    event = Event.recent.first
    assert_equal "run.approved", event.action
    assert_equal run_steps(:awaiting_step_run_step).step.name, event.metadata["step"]
  end

  test "POST reject records a run.rejected event" do
    post reject_run_path(runs(:awaiting_run)), params: { rejection_context: "nope" }
    assert_equal "run.rejected", Event.recent.first.action
  end

  test "POST retry_from records a run.started event for the new run" do
    run = runs(:failed_run)
    post retry_from_run_path(run, step_id: steps(:skill_step).id)
    assert_equal "run.started", Event.recent.first.action
    assert_equal Run.last, Event.recent.first.subject
  end

  test "POST approve records an approval event with actor and comment" do
    run = runs(:awaiting_run)
    rs = run_steps(:awaiting_step_run_step)

    assert_difference "ApprovalEvent.count", 1 do
      post approve_run_path(run), params: { comment: "Looks right to me." }
    end

    event = rs.approval_events.recent.first
    assert_equal "approved", event.action
    assert_equal users(:admin), event.user
    assert_equal "Looks right to me.", event.comment
  end

  test "POST approve without a comment still records the actor" do
    run = runs(:awaiting_run)
    post approve_run_path(run)
    event = run_steps(:awaiting_step_run_step).approval_events.recent.first
    assert_equal users(:admin), event.user
    assert_nil event.comment
  end

  test "POST reject records an approval event carrying the feedback" do
    run = runs(:awaiting_run)
    rs = run_steps(:awaiting_step_run_step)

    assert_difference "ApprovalEvent.count", 1 do
      post reject_run_path(run), params: { rejection_context: "Use a different branch name." }
    end

    event = rs.approval_events.recent.first
    assert_equal "rejected", event.action
    assert_equal "Use a different branch name.", event.comment
    # Regression: the job still keys re-injection off this column.
    assert_equal "Use a different branch name.", rs.reload.rejection_context
  end

  test "a second approver is told who decided first" do
    run = runs(:awaiting_run)
    post approve_run_path(run)

    post approve_run_path(run)
    assert_redirected_to run_path(run)
    assert_equal "Already approved by #{users(:admin).email}.", flash[:alert]
  end

  test "approval history renders on the run page after a decision" do
    run = runs(:awaiting_run)
    post approve_run_path(run), params: { comment: "Ship it." }

    get run_path(run)
    assert_response :success
    assert_match(/Approved/, response.body)
    assert_match "Ship it.", response.body
  end

  # --- R10: Replay + Compare ---

  test "GET replay renders the trajectory view" do
    get replay_run_path(runs(:completed_run))
    assert_response :success
    assert_select "h1", text: /#{runs(:completed_run).pipeline_task.title}/
    assert_select "a", text: "Transcript"
  end

  test "GET replay gives every step and entry an addressable id" do
    run = runs(:completed_run)
    get replay_run_path(run)
    assert_response :success

    run.run_steps.where(parent_run_step_id: nil).find_each do |run_step|
      assert_select "##{"replay_step_#{run_step.id}"}"
    end
    assert_select "li[id^=?]", "entry_"
  end

  test "GET replay offers copy-link buttons anchored to those ids" do
    run_step = runs(:completed_run).run_steps.first
    get replay_run_path(runs(:completed_run))
    assert_response :success
    assert_select "button[data-permalink-anchor-value=?]", "replay_step_#{run_step.id}"
  end

  test "GET replay surfaces stream_log entries from each RunStep" do
    get replay_run_path(runs(:completed_run))
    assert_response :success
    # passed_step's stream_log includes a `result` event (5 turns @ 45s).
    # Render the trajectory entry inline so the "Result" header is visible.
    assert_match(/Result/, response.body)
    assert_match "5 turns", response.body
    assert_match "45.0s", response.body
  end

  test "GET replay renders filter chips for every entry kind" do
    get replay_run_path(runs(:completed_run))
    assert_response :success
    ["tool_use", "text", "thinking", "tool_result", "result", "system"].each do |kind|
      assert_select "input[data-kind=?]", kind
    end
  end

  test "GET diff with no other runs of this task surfaces the empty state" do
    # failed_run has no pipeline_task; fall back to workflow scope.
    # Make sure exactly one other run of the same workflow exists so the
    # dropdown is populated but the user hasn't picked yet.
    get diff_run_path(runs(:failed_run))
    assert_response :success
    # Either picks the default target OR shows the "pick one" empty state.
    assert_select "select[name=against]"
  end

  test "GET diff picks the most recent other run of the same task by default" do
    same_task_run = Run.create!(workflow: workflows(:deploy),
                                pipeline_task: pipeline_tasks(:completed_task),
                                status: "failed", started_at: 1.day.ago,
                                finished_at: 23.hours.ago, context: {}, input: {})

    get diff_run_path(runs(:completed_run))
    assert_response :success
    assert_match "Run ##{same_task_run.id}", response.body
  end

  test "GET diff honors an explicit against= parameter" do
    other = Run.create!(workflow: workflows(:deploy),
                        pipeline_task: pipeline_tasks(:completed_task),
                        status: "completed", started_at: 1.day.ago,
                        finished_at: 23.hours.ago, context: {}, input: {})

    get diff_run_path(runs(:completed_run), against: other.id)
    assert_response :success
    assert_match "Run ##{other.id}", response.body
  end

  test "GET diff ignores against= ids that aren't candidate targets" do
    # A run from an unrelated workflow shouldn't be selectable.
    other_workflow = workflows(:deploy)
    foreign = Run.create!(workflow: other_workflow, status: "completed",
                          started_at: 1.day.ago, finished_at: 23.hours.ago,
                          context: {}, input: {})

    # Make completed_run task-scoped to ensure the candidate pool is just
    # other runs of the same task — foreign isn't part of it.
    get diff_run_path(runs(:completed_run), against: foreign.id)
    assert_response :success
    # Falls through to the empty state because no candidate matched.
    assert_no_match(/Run ##{foreign.id}/, response.body)
  end

  test "all three run modes share one chrome and tab bar" do
    run = runs(:completed_run)

    [run_path(run), replay_run_path(run), diff_run_path(run)].each do |path|
      get path
      assert_response :success
      assert_select "#run_header h1", text: /#{run.pipeline_task.title}/
      assert_select "a[href=?]", run_path(run), text: "Overview"
      assert_select "a[href=?]", replay_run_path(run), text: "Transcript"
      assert_select "a[href=?]", diff_run_path(run), text: "Compare"
      assert_select "[data-controller=?]", "presence"
    end
  end

  test "the header keeps the id and partial that broadcasts target" do
    get run_path(runs(:active_run))
    assert_select "#run_header"
    assert_select "#run_steps_list"
  end

  test "the header carries every run action" do
    run = runs(:completed_run)
    get run_path(run)

    assert_select "form[action=?]", execute_pipeline_task_path(run.pipeline_task)
    assert_select "a[href=?]", run_path(run, anchor: "share"), text: "Share"
  end

  test "an active run offers Stop" do
    get run_path(runs(:active_run))
    assert_select "form[action=?]", stop_run_path(runs(:active_run))
  end

  # C.2: the row says what happened, the raw material is one disclosure deeper.
  test "a failed step leads with the first line of its error" do
    get run_path(runs(:failed_run))
    assert_select "#run_step_#{run_steps(:failed_step).id} summary p", text: /Build failed: missing dependency/
  end

  test "a completed step names what it produced" do
    run = runs(:completed_run)
    run.update!(context: { "pr_number" => "42" })
    steps(:skill_step).update!(config: steps(:skill_step).config.merge("produces" => ["pr_number"]))

    get run_path(run)
    assert_select "#run_step_#{run_steps(:passed_step).id} summary p", text: /Produced pr_number/
  end

  test "a step waiting on approval says so" do
    get run_path(runs(:awaiting_run))
    assert_select "#run_step_#{run_steps(:awaiting_step_run_step).id} summary p", text: /Waiting on a human/
  end

  test "stderr is not in the collapsed row but is present under raw details" do
    failed = run_steps(:failed_step)
    get run_path(runs(:failed_run))

    row = css_select("#run_step_#{failed.id} > div > details > summary").to_s
    assert_not_includes row, "stderr"
    assert_not_includes row, "raw output"

    assert_select "#run_step_#{failed.id} details[data-preserve-key=?]", "raw"
    assert_match(/Raw details/, response.body)
  end

  test "a streaming step opens itself so its live log stays visible" do
    get run_path(runs(:active_run))
    assert_select "#run_step_#{run_steps(:running_step).id} > div > details[open]"
    assert_select "#run_step_#{run_steps(:running_step).id} details[data-preserve-key='raw'][open]"
  end

  test "the run info card carries the raw id" do
    run = runs(:completed_run)
    get run_path(run)
    assert_select "#run_info h2", text: /##{run.id}/
  end

  # ExecuteRunJob broadcasts `replace target: "run_step_<id>", partial:
  # "runs/run_step"`. Rendering it the same way proves the restructured
  # partial still produces an element the broadcast can land on. System tests
  # cannot see broadcasts, so this is the guard against silently killing them.
  test "the broadcast render path still produces the element it targets" do
    run_step = run_steps(:running_step)
    html = ApplicationController.render(
      partial: "runs/run_step",
      locals: { run_step: run_step, run: run_step.run }
    )

    assert_match(/id="run_step_#{run_step.id}"/, html)
    assert_match(/Plan Feature/, html)
  end

  test "the broadcast render path for the header and lists still matches" do
    run = runs(:active_run)

    assert_match(/id="run_header"/, ApplicationController.render(partial: "runs/run_header", locals: { run: run }))
    assert_match(/id="run_info"/, ApplicationController.render(partial: "runs/run_info", locals: { run: run }))
    assert_match(/id="run_context"/, ApplicationController.render(partial: "runs/run_context", locals: { run: run }))
    assert_match(/id="run_steps_list"/, ApplicationController.render(partial: "runs/run_steps_list", locals: { run: run }))
  end

  test "an empty runs list names the next action" do
    Run.destroy_all
    get runs_path
    assert_select "button[data-action=?]", "command-palette#open", text: "Launch your first run"
  end

  test "a filtered runs list offers to clear the filter" do
    get runs_path, params: { status: "stopped" }
    assert_select "a[href=?]", runs_path, text: "Clear filters"
  end
end
