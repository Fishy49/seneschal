require "application_system_test_case"

class TasksTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
  end

  test "list tasks" do
    visit pipeline_tasks_path
    assert_text "Add user authentication"
    assert_text "Refactor database layer"
  end

  test "view task details" do
    visit pipeline_task_path(pipeline_tasks(:ready_task))
    assert_text "Add user authentication"
    assert_text "Seneschal"
  end

  test "create new task" do
    visit new_pipeline_task_path
    fill_in "Title", with: "Brand New Task"
    page.execute_script("document.querySelector('input[name=\"pipeline_task[body]\"]').value = 'Implement this feature'")
    select "Feature", from: "Kind"
    select "Seneschal", from: "Project"
    click_on "Save"

    assert_text "Brand New Task"
  end

  test "edit task" do
    visit edit_pipeline_task_path(pipeline_tasks(:draft_task))
    fill_in "Title", with: "Updated Task Title"
    click_on "Save"

    assert_text "Updated Task Title"
  end

  test "highlight.js loads from local assets" do
    visit new_pipeline_task_path
    assert page.evaluate_script("typeof window.hljs !== 'undefined'"),
           "highlight.js did not load from the vendored asset"
  end

  test "choosing a project narrows the workflow select" do
    other = projects(:other_project).workflows.create!(name: "Other Project Flow")

    visit new_pipeline_task_path
    select "Seneschal", from: "Project"
    assert_select_options "pipeline_task_workflow_id", includes: "Deploy Pipeline", excludes: other.name

    select "OtherProject", from: "Project"
    assert_select_options "pipeline_task_workflow_id", includes: other.name, excludes: "Deploy Pipeline"
  end

  test "save and run starts a run in one submission" do
    visit new_pipeline_task_path
    fill_in "Title", with: "Launch straight away"
    page.execute_script("document.querySelector('input[name=\"pipeline_task[body]\"]').value = 'Do the thing'")
    select "Seneschal", from: "Project"
    select "Deploy Pipeline", from: "Workflow"
    click_on "Save & Run"

    assert_text "Run started for 'Launch straight away'"
  end

  private

  def assert_select_options(select_id, includes:, excludes:)
    options = find("##{select_id}").all("option", visible: :all).map(&:text)
    assert_includes options, includes
    assert_not_includes options, excludes
  end

  test "filter tasks by status" do
    visit pipeline_tasks_path
    select "Ready", from: "status"
    click_on "Search"

    assert_text "Add user authentication"
  end

  test "task shows runs" do
    visit pipeline_task_path(pipeline_tasks(:completed_task))
    assert_text "Runs"
  end
end
