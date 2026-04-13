require "test_helper"

class StepsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @project = projects(:seneschal)
    @workflow = workflows(:deploy)
  end

  test "GET new renders form" do
    get new_project_workflow_step_path(@project, @workflow)
    assert_response :success
  end

  test "POST create skill step" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "New Skill Step",
          step_type: "skill",
          skill_id: skills(:shared_skill).id,
          position: 10,
          timeout: 300,
          max_retries: 0
        }
      }
    end
    assert_redirected_to project_workflow_path(@project, @workflow)
  end

  test "POST create command step" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "New Command",
          step_type: "command",
          body: "echo hello",
          position: 10,
          timeout: 60,
          max_retries: 0
        }
      }
    end
    assert_redirected_to project_workflow_path(@project, @workflow)
  end

  test "POST create with invalid params" do
    assert_no_difference "Step.count" do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: { name: "", step_type: "skill", position: 10 }
      }
    end
    assert_response :unprocessable_content
  end

  test "GET edit renders form" do
    get edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))
    assert_response :success
  end

  test "PATCH update" do
    patch project_workflow_step_path(@project, @workflow, steps(:skill_step)), params: {
      step: { name: "Updated Name" }
    }
    assert_redirected_to project_workflow_path(@project, @workflow)
    assert_equal "Updated Name", steps(:skill_step).reload.name
  end

  test "DELETE destroy removes step" do
    step = @workflow.steps.create!(name: "Temp", step_type: "command", body: "echo x", position: 99)
    assert_difference "Step.count", -1 do
      delete project_workflow_step_path(@project, @workflow, step)
    end
    assert_redirected_to project_workflow_path(@project, @workflow)
  end

  test "PATCH move updates position" do
    patch move_project_workflow_step_path(@project, @workflow, steps(:skill_step)), params: { position: 5 }
    assert_redirected_to project_workflow_path(@project, @workflow)
    assert_equal 5, steps(:skill_step).reload.position
  end

  test "POST create with save_as_template creates both step and template" do
    assert_difference ["Step.count", "StepTemplate.count"], 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Reusable Command",
          step_type: "command",
          body: "make build",
          position: 10,
          timeout: 120,
          max_retries: 1
        },
        save_as_template: "1",
        template_name: "Build Step"
      }
    end
    template = StepTemplate.find_by(name: "Build Step")
    assert_not_nil template
    assert_equal "command", template.step_type
    assert_equal "make build", template.body
    assert_equal 120, template.timeout
  end

  test "POST create without save_as_template does not create template" do
    assert_no_difference "StepTemplate.count" do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "No Template",
          step_type: "command",
          body: "echo hi",
          position: 10
        }
      }
    end
  end

  test "GET new shows template selector when templates exist" do
    get new_project_workflow_step_path(@project, @workflow)
    assert_response :success
    assert_select "[data-controller*='template-panel']"
  end
end
