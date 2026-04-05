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
end
