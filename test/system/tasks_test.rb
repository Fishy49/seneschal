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
    fill_in_spec "Implement this feature"
    select "Seneschal", from: "Project"
    click_on "Save draft"

    assert_text "Brand New Task"
  end

  test "edit task" do
    visit edit_pipeline_task_path(pipeline_tasks(:draft_task))
    fill_in "Title", with: "Updated Task Title"
    click_on "Save draft"

    assert_text "Updated Task Title"
  end

  test "highlight.js loads from local assets" do
    visit new_pipeline_task_path
    assert page.evaluate_script("typeof window.hljs !== 'undefined'"),
           "highlight.js did not load from the vendored asset"
  end

  test "choosing a project narrows the workflow cards" do
    other = projects(:other_project).workflows.create!(name: "Other Project Flow")

    visit new_pipeline_task_path
    select "Seneschal", from: "Project"
    assert_selector "label", text: "Deploy Pipeline"
    assert_no_selector "label", text: other.name

    select "OtherProject", from: "Project"
    assert_selector "label", text: other.name
    assert_no_selector "label", text: "Deploy Pipeline"
  end

  test "a workflow card carries its stats and what it can touch" do
    visit new_pipeline_task_path
    select "Seneschal", from: "Project"

    within("label", text: "Deploy Pipeline") do
      assert_text(/step/)
      assert_text(/never run|runs/)
    end
  end

  test "launching composes and starts a run in one submission" do
    visit new_pipeline_task_path
    fill_in "Title", with: "Launch straight away"
    fill_in_spec "Do the thing"
    select "Seneschal", from: "Project"
    choose_workflow "Deploy Pipeline"
    click_on "Launch"

    assert_text "Run started for 'Launch straight away'"
  end

  test "the composer prefills from a palette handoff" do
    visit new_pipeline_task_path(description: "Add rate limiting", project_id: projects(:seneschal).id)
    assert_field "Title", with: "Add rate limiting"
  end

  test "the board groups tasks into status columns" do
    visit pipeline_tasks_path

    assert_text "Draft"
    assert_text "Waiting on you"
    within("[data-column='ready']") { assert_text "Add user authentication" }
    within("[data-column='draft']") { assert_text "Refactor database layer" }
  end

  test "task shows runs" do
    visit pipeline_task_path(pipeline_tasks(:completed_task))
    assert_text "Runs"
  end

  private

  # The spec field is a CodeJar editor writing into a hidden input.
  def fill_in_spec(text)
    page.execute_script(
      "document.querySelector('input[name=\"pipeline_task[body]\"]').value = arguments[0]", text
    )
  end

  def choose_workflow(name)
    find("label", text: name).click
  end
end
