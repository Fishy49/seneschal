require "test_helper"

# The sidebar is the contract for "everything is still reachable". These
# assertions pin the six-section shape from PRODUCT_REDESIGN.md section 4.1.
class NavigationTest < ActionDispatch::IntegrationTest
  test "the sidebar shows the six sections" do
    sign_in users(:admin)
    get root_path

    assert_select "nav" do
      assert_select "a[href=?]", root_path, text: "Home"
      assert_select "a[href=?]", runs_path
      assert_select "a[href=?]", projects_path, text: "Projects"
      assert_select "a[href=?]", skills_path, text: "Library"
      assert_select "a[href=?]", activity_path, text: "Activity"
    end
  end

  test "the sidebar no longer links the library pages directly" do
    sign_in users(:admin)
    get root_path

    assert_select "nav a", text: "Skill Repos", count: 0
    assert_select "nav a", text: "Schemas", count: 0
    assert_select "nav a", text: "Templates", count: 0
    assert_select "nav a", text: "Tasks", count: 0
    assert_select "nav a", text: "Enable 2FA", count: 0
  end

  test "the admin section is admin only" do
    sign_in users(:admin)
    get root_path
    assert_select "nav a[href=?]", users_path, text: "Users"
    assert_select "nav a[href=?]", data_management_path, text: "Data"

    sign_in users(:other)
    get root_path
    assert_select "nav a[href=?]", users_path, count: 0
    assert_select "nav a[href=?]", data_management_path, count: 0
  end

  test "the sidebar carries a Launch button wired to the palette" do
    sign_in users(:admin)
    get root_path

    assert_select "nav button[data-action=?]", "command-palette#open"
    assert_select "body[data-controller=?]", "command-palette"
  end

  test "library pages carry the library tabs" do
    sign_in users(:admin)

    [skills_path, json_schemas_path, step_templates_path, skill_repos_path].each do |path|
      get path
      assert_select "a[href=?]", skills_path, text: "Skills"
      assert_select "a[href=?]", json_schemas_path, text: "Output schemas"
      assert_select "a[href=?]", step_templates_path, text: "Templates"
      assert_select "a[href=?]", skill_repos_path, text: "Skill repos"
    end
  end

  test "members do not see the skill repos tab" do
    sign_in users(:other)
    get skills_path

    assert_select "a[href=?]", json_schemas_path, text: "Output schemas"
    assert_select "a[href=?]", skill_repos_path, count: 0
  end

  test "admin pages carry the admin tabs" do
    sign_in users(:admin)

    [users_path, project_groups_path, admin_settings_path, data_management_path, setup_path].each do |path|
      get path
      assert_select "a[href=?]", users_path, text: "Users"
      assert_select "a[href=?]", project_groups_path, text: "Groups"
      assert_select "a[href=?]", admin_settings_path, text: "Server settings"
      assert_select "a[href=?]", setup_path, text: "Health checks"
    end
  end
end
