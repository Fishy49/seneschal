require "test_helper"
require "tmpdir"

class WorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @project = projects(:seneschal)
    @workflow = workflows(:deploy)
  end

  # Importing a starter materialises shared SKILL.md files. Redirect the global
  # skills root at a temp dir first, or the test writes into the repo's own
  # fixture tree and leaves the working copy dirty.
  def with_temporary_skills_root
    Dir.mktmpdir("seneschal-import") do |dir|
      Setting["skills_global_roots"] = dir
      yield
    ensure
      Setting["skills_global_roots"] = FilesystemSkillFixtures::FIXTURE_SKILLS_ROOT
    end
  end

  test "GET show displays workflow" do
    get project_workflow_path(@project, @workflow)
    assert_response :success
  end

  test "GET new renders form" do
    get new_project_workflow_path(@project)
    assert_response :success
  end

  test "POST create with valid params" do
    assert_difference "Workflow.count", 1 do
      post project_workflows_path(@project), params: {
        workflow: { name: "New Workflow" }
      }
    end
    assert_redirected_to project_workflow_path(@project, Workflow.last)
  end

  test "POST create with invalid params" do
    assert_no_difference "Workflow.count" do
      post project_workflows_path(@project), params: {
        workflow: { name: "" }
      }
    end
    assert_response :unprocessable_content
  end

  test "GET edit renders form" do
    get edit_project_workflow_path(@project, @workflow)
    assert_response :success
  end

  test "PATCH update" do
    patch project_workflow_path(@project, @workflow), params: {
      workflow: { description: "Updated" }
    }
    assert_redirected_to project_workflow_path(@project, @workflow)
  end

  test "show offers a delete button" do
    get project_workflow_path(@project, @workflow)
    assert_select "form[action=?][method=?]", project_workflow_path(@project, @workflow), "post"
    assert_select "input[value='delete'][name='_method']"
  end

  test "there is no workflow index" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/projects/#{@project.id}/workflows", method: :get)
    end
  end

  test "DELETE destroy removes workflow" do
    workflow = @project.workflows.create!(name: "Disposable")
    assert_difference "Workflow.count", -1 do
      delete project_workflow_path(@project, workflow)
    end
    assert_redirected_to project_path(@project)
  end

  test "POST trigger creates run and enqueues job" do
    assert_difference "Run.count", 1 do
      assert_enqueued_with(job: ExecuteRunJob) do
        post trigger_project_workflow_path(@project, @workflow), as: :json
      end
    end
    assert_redirected_to run_path(Run.last)
  end

  test "POST create records a workflow.created event" do
    post project_workflows_path(@project), params: { workflow: { name: "Evented" } }
    assert_equal "workflow.created", Event.recent.first.action
    assert_equal Workflow.last, Event.recent.first.subject
  end

  test "PATCH update records a workflow.updated event" do
    patch project_workflow_path(@project, @workflow), params: { workflow: { description: "changed" } }
    assert_equal "workflow.updated", Event.recent.first.action
  end

  test "POST trigger records a run.started event" do
    post trigger_project_workflow_path(@project, @workflow), as: :json
    assert_equal "run.started", Event.recent.first.action
  end

  test "GET show offers a Run workflow button when the repo is ready" do
    get project_workflow_path(@project, @workflow)
    assert_response :success
    assert_select "form[action=?]", trigger_project_workflow_path(@project, @workflow)
  end

  test "GET show disables Run workflow when the repo is not cloned" do
    project = projects(:other_project)
    workflow = project.workflows.create!(name: "Unclonable")
    get project_workflow_path(project, workflow)
    assert_response :success
    assert_select "form[action=?]", trigger_project_workflow_path(project, workflow), false
  end

  test "PATCH update sets workflow.config[runner] when the form picks one" do
    patch project_workflow_path(@project, @workflow), params: {
      workflow: { name: @workflow.name, description: @workflow.description.to_s, runner: "claude_sdk" }
    }
    # A redirect means the controller didn't blow up on UnfilteredParameters
    # — earlier the request silently raised mid-mass-assignment and the
    # config-key assertion below would still happen to pass on stale state.
    assert_response :redirect
    assert_equal "claude_sdk", @workflow.reload.config["runner"]
  end

  test "PATCH update clears workflow.config[runner] when the form picks the default" do
    @workflow.update!(config: { "runner" => "claude_sdk" })
    patch project_workflow_path(@project, @workflow), params: {
      workflow: { name: @workflow.name, description: @workflow.description.to_s, runner: "" }
    }
    assert_response :redirect
    assert_not @workflow.reload.config.key?("runner")
  end

  test "GET export downloads a JSON workflow export" do
    get export_project_workflow_path(@project, @workflow)

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment; filename="workflow-deploy-pipeline-/, response.headers["Content-Disposition"])

    body = response.parsed_body
    assert_equal 1, body["seneschal_workflow_export"]["version"]
    assert_equal "Deploy Pipeline", body["seneschal_workflow_export"]["workflow"]["name"]
  end

  test "PATCH update refuses an unknown runner value rather than persisting garbage" do
    patch project_workflow_path(@project, @workflow), params: {
      workflow: { name: @workflow.name, description: @workflow.description.to_s, runner: "fake_runner_lol" }
    }
    assert_response :redirect
    assert_not_includes @workflow.reload.config.fetch("runner", "missing"), "fake"
  end

  test "GET new leads with the starter gallery" do
    get new_project_workflow_path(@project)
    assert_select "h2", text: "Start from a template"
    Seneschal::StarterTemplates.list.each do |template|
      assert_select "h3", text: template.name
    end
    assert_select "h2", text: "Start blank"
  end

  test "POST create_from_template builds a wired workflow" do
    with_temporary_skills_root do
      assert_difference "Workflow.count", 1 do
        post create_from_template_project_workflows_path(@project), params: { template: "classic_feature" }
      end

      workflow = Workflow.last
      assert_redirected_to project_workflow_path(@project, workflow)
      assert_equal @project.id, workflow.project_id
      assert_equal users(:admin), workflow.created_by
      assert_equal ["skill", "skill", "self_review", "pr", "ci_check"],
                   workflow.steps.order(:position).map(&:step_type)
      assert(workflow.steps.where(step_type: "skill").all? { |s| s.skill.present? })
    end
  end

  test "POST create_from_template records the creation event" do
    with_temporary_skills_root do
      post create_from_template_project_workflows_path(@project), params: { template: "bugfix" }
      assert_equal "workflow.created", Event.recent.first.action
    end
  end

  test "using the same template twice suffixes rather than failing" do
    with_temporary_skills_root do
      post create_from_template_project_workflows_path(@project), params: { template: "docs_pass" }
      first = Workflow.last

      assert_difference "Workflow.count", 1 do
        post create_from_template_project_workflows_path(@project), params: { template: "docs_pass" }
      end
      assert_not_equal first.name, Workflow.last.name
    end
  end

  test "POST create_from_template rejects an unknown template" do
    assert_no_difference "Workflow.count" do
      post create_from_template_project_workflows_path(@project), params: { template: "../../etc/passwd" }
    end
    assert_redirected_to new_project_workflow_path(@project)
  end
end
