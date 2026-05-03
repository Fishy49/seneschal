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

  test "manual_approval flag persists on create" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Approve me",
          step_type: "command",
          body: "echo hi",
          position: 20,
          timeout: 60,
          max_retries: 0,
          manual_approval: "1"
        }
      }
    end
    assert_redirected_to project_workflow_path(@project, @workflow)
    assert Step.find_by(name: "Approve me").manual_approval
  end

  test "manual_approval flag persists on update" do
    patch project_workflow_step_path(@project, @workflow, steps(:command_step)), params: {
      step: { manual_approval: "1" }
    }
    assert steps(:command_step).reload.manual_approval
  end

  test "GET edit shows manual_approval checkbox" do
    get edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))
    assert_response :success
    assert_select "input[type=checkbox][name='step[manual_approval]']"
  end

  test "manual_approval is carried into save_as_template" do
    assert_difference "StepTemplate.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Approval Template Step",
          step_type: "command",
          body: "echo ok",
          position: 21,
          timeout: 60,
          max_retries: 0,
          manual_approval: "1"
        },
        save_as_template: "1",
        template_name: "Approval Template"
      }
    end
    template = StepTemplate.find_by(name: "Approval Template")
    assert_not_nil template
    assert template.manual_approval
  end

  test "POST create skill step with json_schema_id persists it in config" do
    schema = json_schemas(:person_schema)
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Schema Skill",
          step_type: "skill",
          skill_id: skills(:shared_skill).id,
          position: 50,
          timeout: 60,
          max_retries: 0
        },
        json_schema_id: schema.id.to_s
      }
    end
    assert_equal schema.id, Step.last.config["json_schema_id"]
  end

  test "POST create json_validator step auto-includes source variable in consumes" do
    schema = json_schemas(:person_schema)
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Validator",
          step_type: "json_validator",
          position: 99,
          timeout: 30,
          max_retries: 0
        },
        json_validator_schema_id: schema.id.to_s,
        json_validator_source_variable: "payload"
      }
    end
    assert_includes Step.last.config["consumes"], "payload"
  end

  test "GET edit renders produces-input controller" do
    get edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))
    assert_response :success
    assert_match "data-controller=\"produces-input\"", response.body
    assert_select "input[type=hidden][name=produces]"
  end

  test "GET produces_suggestions returns global variables and existing produces" do
    steps(:skill_step).update!(config: { "produces" => ["custom_var"] })
    get produces_suggestions_project_workflow_steps_path(@project, @workflow)
    assert_response :success
    data = response.parsed_body
    Step::GLOBAL_VARIABLES.each do |gv|
      assert_includes data["suggestions"], gv
    end
    assert_includes data["suggestions"], "custom_var"
  end

  test "POST create persists produces as array" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Producer",
          step_type: "command",
          body: "echo hi",
          position: 60,
          timeout: 30,
          max_retries: 0
        },
        produces: "alpha,beta"
      }
    end
    assert_equal ["alpha", "beta"], Step.last.config["produces"]
    assert_equal ["alpha", "beta"], Step.last.produces
  end
end
