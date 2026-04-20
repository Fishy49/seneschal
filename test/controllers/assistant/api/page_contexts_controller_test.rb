require "test_helper"

module Assistant
  module Api
    class PageContextsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @conversation = assistant_conversations(:admin_conversation)
        @token = @conversation.turbo_token
      end

      test "GET show returns 401 without token" do
        get assistant_api_page_contexts_path, params: { path: "/" }
        assert_response :unauthorized
      end

      test "GET show returns context for a project path" do
        project = projects(:seneschal)
        get assistant_api_page_contexts_path,
            params: { path: "/projects/#{project.id}" },
            headers: auth_headers
        assert_response :success
        data = JSON.parse(response.body)
        assert_equal "projects", data["controller"]
        assert_equal project.id, data.dig("record", "id")
        assert_equal project.name, data.dig("record", "name")
      end

      test "GET show returns fallback for unknown path" do
        get assistant_api_page_contexts_path,
            params: { path: "/nonexistent/path/xyz" },
            headers: auth_headers
        assert_response :success
        data = JSON.parse(response.body)
        assert_equal "/nonexistent/path/xyz", data["path"]
      end

      private

      def auth_headers
        { "Authorization" => "Bearer #{@token}" }
      end
    end
  end
end
