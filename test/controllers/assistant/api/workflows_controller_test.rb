require "test_helper"

module Assistant
  module Api
    class WorkflowsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @conversation = assistant_conversations(:admin_conversation)
        @token = @conversation.turbo_token
        @project = projects(:seneschal)
        @workflow = workflows(:deploy)
      end

      test "GET index returns 401 without token" do
        get assistant_api_project_workflows_path(project_id: @project)
        assert_response :unauthorized
      end

      test "GET index lists workflows for project" do
        get assistant_api_project_workflows_path(project_id: @project), headers: auth_headers
        assert_response :success
        data = response.parsed_body
        assert_kind_of Array, data
        names = data.pluck("name")
        assert_includes names, @workflow.name
      end

      test "POST create creates workflow" do
        assert_difference "Workflow.count", 1 do
          post assistant_api_project_workflows_path(project_id: @project),
               params: { name: "New Workflow", trigger_type: "manual" },
               headers: auth_headers
        end
        assert_response :created
        data = response.parsed_body
        assert_equal "New Workflow", data["name"]
      end

      test "POST trigger creates run and enqueues job" do
        assert_difference "Run.count", 1 do
          assert_enqueued_with(job: ExecuteRunJob) do
            post trigger_assistant_api_project_workflow_path(project_id: @project, id: @workflow),
                 headers: auth_headers
          end
        end
        assert_response :created
      end

      test "DELETE destroy removes workflow" do
        workflow = @project.workflows.create!(name: "Temp", trigger_type: "manual")
        assert_difference "Workflow.count", -1 do
          delete assistant_api_project_workflow_path(project_id: @project, id: workflow), headers: auth_headers
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
