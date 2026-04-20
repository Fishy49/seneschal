require "test_helper"

module Assistant
  module Api
    class SkillsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @conversation = assistant_conversations(:admin_conversation)
        @token = @conversation.turbo_token
      end

      test "GET index returns 401 without token" do
        get assistant_api_skills_path
        assert_response :unauthorized
      end

      test "GET index lists skills" do
        get assistant_api_skills_path, headers: auth_headers
        assert_response :success
        data = response.parsed_body
        assert_kind_of Array, data
      end

      test "POST create creates a shared skill" do
        assert_difference "Skill.count", 1 do
          post assistant_api_skills_path,
               params: { name: "My New Skill", body: "Do something useful", description: "Test" },
               headers: auth_headers
        end
        assert_response :created
        data = response.parsed_body
        assert data["shared"]
      end

      test "POST create creates a project skill" do
        project = projects(:seneschal)
        assert_difference "Skill.count", 1 do
          post assistant_api_skills_path,
               params: { name: "Project Skill", body: "Project body", project_id: project.id },
               headers: auth_headers
        end
        assert_response :created
        data = response.parsed_body
        assert_equal project.id, data["project_id"]
      end

      test "DELETE destroy removes skill" do
        skill = skills(:shared_skill)
        assert_difference "Skill.count", -1 do
          delete assistant_api_skill_path(skill), headers: auth_headers
        end
        assert_response :no_content
      end

      private

      def auth_headers
        { "Authorization" => "Bearer #{@token}" }
      end
    end
  end
end
