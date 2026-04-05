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
    click_on "Create Pipeline task"

    assert_text "Brand New Task"
  end

  test "edit task" do
    visit edit_pipeline_task_path(pipeline_tasks(:draft_task))
    fill_in "Title", with: "Updated Task Title"
    click_on "Update Pipeline task"

    assert_text "Updated Task Title"
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
