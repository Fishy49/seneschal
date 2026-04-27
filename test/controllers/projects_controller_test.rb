require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists projects" do
    get projects_path
    assert_response :success
  end

  test "GET show displays project" do
    get project_path(projects(:seneschal))
    assert_response :success
  end

  test "GET new renders form" do
    get new_project_path
    assert_response :success
  end

  test "POST create with valid params" do
    assert_difference "Project.count", 1 do
      post projects_path, params: {
        project: {
          name: "BrandNew",
          repo_url: "https://github.com/test/brandnew.git",
          local_path: Rails.root.join("tmp/test_repos/brandnew").to_s
        }
      }
    end
    assert_redirected_to project_path(Project.last)
  end

  test "POST create with invalid params" do
    assert_no_difference "Project.count" do
      post projects_path, params: {
        project: { name: "", repo_url: "", local_path: "" }
      }
    end
    assert_response :unprocessable_content
  end

  test "GET edit renders form" do
    get edit_project_path(projects(:seneschal))
    assert_response :success
  end

  test "PATCH update with valid params" do
    patch project_path(projects(:seneschal)), params: {
      project: { description: "Updated description" }
    }
    assert_redirected_to project_path(projects(:seneschal))
    assert_equal "Updated description", projects(:seneschal).reload.description
  end

  test "DELETE destroy removes project" do
    project = projects(:other_project)
    assert_difference "Project.count", -1 do
      delete project_path(project)
    end
    assert_redirected_to projects_path
  end

  test "POST clone enqueues job" do
    assert_enqueued_with(job: CloneRepoJob) do
      post clone_project_path(projects(:seneschal))
    end
    assert_redirected_to project_path(projects(:seneschal))
  end

  test "requires authentication" do
    delete logout_path
    get projects_path
    assert_redirected_to login_path
  end

  test "POST create stores markdown_context" do
    assert_difference "Project.count", 1 do
      post projects_path, params: {
        project: {
          name: "WithCtx",
          repo_url: "https://github.com/test/withctx.git",
          local_path: Rails.root.join("tmp/test_repos/withctx").to_s,
          markdown_context: "# Hello\n\nGuidelines here."
        }
      }
    end
    assert_redirected_to project_path(Project.last)
    assert_equal "# Hello\n\nGuidelines here.", Project.last.markdown_context
  end

  test "PATCH update modifies markdown_context" do
    patch project_path(projects(:seneschal)), params: {
      project: { markdown_context: "# Updated\n\nNew guidelines." }
    }
    assert_redirected_to project_path(projects(:seneschal))
    assert_equal "# Updated\n\nNew guidelines.", projects(:seneschal).reload.markdown_context
  end

  test "GET new and edit render markdown_context preview field" do
    get new_project_path
    assert_response :success
    assert_select "div[data-controller=\"code-editor\"]"
    assert_select "input[name=\"project[markdown_context]\"][type=\"hidden\"]"

    get edit_project_path(projects(:seneschal))
    assert_response :success
    assert_select "div[data-controller=\"code-editor\"]"
    assert_select "input[name=\"project[markdown_context]\"][type=\"hidden\"]"
  end

  test "GET projects index filters by group_id" do
    get projects_path, params: { group_id: project_groups(:frontend).id }
    assert_response :success
    assert_select "h3", text: /Seneschal/
    assert_select "h3", text: /OtherProject/, count: 0
  end

  test "GET projects index group_id=none shows only ungrouped" do
    get projects_path, params: { group_id: "none" }
    assert_response :success
    assert_select "h3", text: /OtherProject/
    assert_select "h3", text: /\ASeneschal\z/, count: 0
  end

  test "GET edit renders group select and danger toggle" do
    get edit_project_path(projects(:seneschal))
    assert_response :success
    assert_select "select[name='project[project_group_id]']"
    assert_select "input[type='checkbox'][name='project[skip_permissions]']"
  end

  test "PATCH update toggles skip_permissions" do
    projects(:seneschal).update!(skip_permissions: false)
    patch project_path(projects(:seneschal)), params: { project: { skip_permissions: "1" } }
    assert_redirected_to project_path(projects(:seneschal))
    assert_equal true, projects(:seneschal).reload.skip_permissions
  end
end
