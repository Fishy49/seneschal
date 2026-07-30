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
    find("summary", text: "New").click
    click_on "Workflow"
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

  test "a step opens and saves in the inspector without leaving the workflow" do
    workflow = workflows(:deploy)
    visit project_workflow_path(@project, workflow)
    assert_text "Select a step to edit it."

    click_on "Plan Feature"
    assert_selector "turbo-frame#step_inspector h2", text: "Edit step"

    within("turbo-frame#step_inspector") do
      fill_in "Name", with: "Plan the feature"
      click_on "Save step"
    end

    assert_selector "#workflow_steps", text: "Plan the feature"
    assert_current_path project_workflow_path(@project, workflow)
  end

  test "a step added without a position lands at the end" do
    workflow = workflows(:deploy)
    visit project_workflow_path(@project, workflow)
    click_on "+ Add step"
    assert_selector "turbo-frame#step_inspector h2", text: "Add step"

    # Choosing a type re-fetches the inspector with only that type's fields.
    select "Shell", from: "Type"
    assert_selector "turbo-frame#step_inspector textarea[name='step[body]']"

    within("turbo-frame#step_inspector") do
      fill_in "Name", with: "Tail end"
      find("textarea[name='step[body]']").set("echo done")
      click_on "Save step"
    end

    assert_selector "#workflow_steps", text: "Tail end"
    assert_equal workflow.steps.maximum(:position), Step.find_by(name: "Tail end").position
  end

  test "each step type shows only its own fields" do
    visit project_workflow_path(@project, workflows(:deploy))
    click_on "+ Add step"
    assert_selector "turbo-frame#step_inspector h2", text: "Add step"

    select "Open PR", from: "Type"
    assert_selector "input#pr_title"
    assert_no_selector "select#ci_mode"

    select "Wait for CI", from: "Type"
    assert_selector "select#ci_mode"
    assert_no_selector "input#pr_title"
  end

  test "switching a saved step's type warns before discarding its settings" do
    workflow = workflows(:deploy)
    workflow.steps.create!(name: "Ships it", step_type: "pr", position: 90,
                           config: { "title" => "feat: something", "base" => "main" })

    visit project_workflow_path(@project, workflow)
    click_on "Ships it"
    assert_selector "turbo-frame#step_inspector input#pr_title"

    select "Shell", from: "Type"
    assert_text "Switching to Shell clears this step's Open PR settings."
    assert_selector "input#pr_title", visible: :all

    click_on "Switch anyway"
    assert_selector "turbo-frame#step_inspector textarea[name='step[body]']"
    assert_no_selector "input#pr_title"
  end

  test "a self review step can be created from the inspector" do
    workflow = workflows(:deploy)
    visit project_workflow_path(@project, workflow)
    click_on "+ Add step"
    assert_selector "turbo-frame#step_inspector h2", text: "Add step"

    select "Self review", from: "Type"
    assert_selector "turbo-frame#step_inspector textarea#review_focus"

    within("turbo-frame#step_inspector") do
      fill_in "Name", with: "Check my own work"
      fill_in "review_focus", with: "Look at the error handling."
      click_on "Save step"
    end

    assert_selector "#workflow_steps", text: "Check my own work"
    created = Step.find_by(name: "Check my own work")
    assert_equal "self_review", created.step_type
    assert_equal "Look at the error handling.", created.config["focus"]
  end
end
