require "application_system_test_case"

class ProjectsTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
  end

  test "list projects" do
    visit projects_path
    assert_text "Seneschal"
    assert_text "OtherProject"
  end

  test "view project details" do
    visit project_path(projects(:seneschal))
    assert_text "Seneschal"
    assert_text "Deploy Pipeline"
  end

  test "create new project" do
    visit new_project_path
    fill_in "Name", with: "MyNewProject"
    fill_in "Repository URL", with: "https://github.com/test/mynew.git"
    fill_in "Local Path", with: Rails.root.join("tmp/test_repos/mynew").to_s
    click_on "Create Project"

    assert_text "MyNewProject"
    assert_text "github.com/test/mynew"
  end

  test "create project with missing name shows error" do
    visit new_project_path
    fill_in "Repository URL", with: "https://github.com/test/x.git"
    fill_in "Local Path", with: "/tmp/x"
    click_on "Create Project"

    assert_text "can't be blank"
  end

  test "edit project" do
    visit edit_project_path(projects(:seneschal))
    fill_in "Description", with: "Updated via system test"
    click_on "Update Project"

    assert_text "Updated via system test"
  end

  test "navigate from dashboard to project" do
    visit root_path
    click_on "Seneschal"
    assert_text "Seneschal"
  end

  test "navigate to workflows from project" do
    visit project_path(projects(:seneschal))
    first(:link, "Deploy Pipeline").click
    assert_text "Steps"
  end
end
