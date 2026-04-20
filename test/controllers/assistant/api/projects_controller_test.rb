require "test_helper"

module Assistant
  module Api
    class ProjectsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @conversation = assistant_conversations(:admin_conversation)
        @token = @conversation.turbo_token
      end

      test "GET index returns projects with valid token" do
        get assistant_api_projects_path, headers: auth_headers
        assert_response :success
        data = JSON.parse(response.body)
        assert_kind_of Array, data
      end

      test "GET index returns 401 without token" do
        get assistant_api_projects_path
        assert_response :unauthorized
      end

      test "GET index returns 401 with invalid token" do
        get assistant_api_projects_path, headers: { "Authorization" => "Bearer invalid" }
        assert_response :unauthorized
      end

      test "GET show returns project" do
        project = projects(:seneschal)
        get assistant_api_project_path(project), headers: auth_headers
        assert_response :success
        data = JSON.parse(response.body)
        assert_equal project.id, data["id"]
        assert_equal project.name, data["name"]
      end

      test "POST create creates project" do
        assert_difference "Project.count", 1 do
          post assistant_api_projects_path,
               params: { name: "New Project", repo_url: "https://github.com/user/repo", local_path: "/tmp/repo" },
               headers: auth_headers
        end
        assert_response :created
      end

      test "PATCH update modifies project" do
        project = projects(:seneschal)
        patch assistant_api_project_path(project),
              params: { name: "Updated Name" },
              headers: auth_headers
        assert_response :success
        assert_equal "Updated Name", project.reload.name
      end

      private

      def auth_headers
        { "Authorization" => "Bearer #{@token}" }
      end
    end
  end
end
