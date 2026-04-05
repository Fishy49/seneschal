require "application_system_test_case"

class WorkflowsTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
    @project = projects(:seneschal)
  end

  test "view workflow with steps" do
    visit project_workflow_path(@project, workflows(:deploy))
    assert_text "Deploy Pipeline"
    assert_text "Plan Feature"
    assert_text "Run Build"
    assert_text "Deploy Script"
  end

  test "create new workflow" do
    visit project_path(@project)
    click_on "New Workflow"
    fill_in "Name", with: "Test Workflow"
    click_on "Create Workflow"

    assert_text "Test Workflow"
  end

  test "edit workflow" do
    visit edit_project_workflow_path(@project, workflows(:deploy))
    fill_in "Description", with: "Edited workflow"
    click_on "Update Workflow"

    assert_text "Edited workflow"
  end

  test "workflow shows recent runs" do
    visit project_workflow_path(@project, workflows(:deploy))
    assert_text "Runs"
  end
end
