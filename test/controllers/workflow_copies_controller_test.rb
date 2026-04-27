require "test_helper"

class WorkflowCopiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @source_project = projects(:seneschal)
    @source_workflow = workflows(:deploy)
    @target_project = projects(:other_project)
  end

  test "GET new shows other projects as options" do
    get new_project_workflow_copy_path(@source_project, @source_workflow)
    assert_response :success
    assert_match "OtherProject", response.body
    assert_no_match(/value="#{@source_project.id}"/, response.body)
  end

  test "POST create copies workflow and redirects" do
    assert_difference "Workflow.count", 1 do
      post project_workflow_copy_path(@source_project, @source_workflow),
           params: { target_project_id: @target_project.id }
    end
    copied = Workflow.where(project: @target_project, name: "Deploy Pipeline").last
    assert_not_nil copied
    assert_redirected_to project_workflow_path(@target_project, copied)
    assert_match(/Workflow copied to OtherProject/, flash[:notice])
  end

  test "POST create includes missing-skill notice in flash" do
    wf = @source_project.workflows.create!(name: "Skill Wf", trigger_type: "manual")
    wf.steps.create!(
      name: "Check Step",
      step_type: "skill",
      skill: skills(:project_skill),
      position: 1,
      timeout: 300,
      max_retries: 0,
      config: {}
    )
    post project_workflow_copy_path(@source_project, wf),
         params: { target_project_id: @target_project.id }
    assert_match(/will reference the original project/, flash[:notice])
  end

  test "requires authentication" do
    delete logout_path
    get new_project_workflow_copy_path(@source_project, @source_workflow)
    assert_redirected_to login_path
  end
end
