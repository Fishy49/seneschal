require "test_helper"

module Assistant
  module Api
    class StepsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @conversation = assistant_conversations(:admin_conversation)
        @token = @conversation.turbo_token
        @project = projects(:seneschal)
        @workflow = workflows(:deploy)
      end

      test "GET index returns 401 without token" do
        get assistant_api_project_workflow_steps_path(project_id: @project, workflow_id: @workflow)
        assert_response :unauthorized
      end

      test "GET index lists steps for workflow" do
        get assistant_api_project_workflow_steps_path(project_id: @project, workflow_id: @workflow), headers: auth_headers
        assert_response :success
        data = response.parsed_body
        assert_kind_of Array, data
      end

      test "POST create adds step to workflow" do
        assert_difference "Step.count", 1 do
          post assistant_api_project_workflow_steps_path(project_id: @project, workflow_id: @workflow),
               params: { name: "New Step", step_type: "prompt", body: "Do the thing" },
               headers: auth_headers
        end
        assert_response :created
      end

      test "POST reorder updates step positions" do
        step1 = @workflow.steps.create!(name: "Step A", step_type: "prompt", body: "A", position: 1)
        step2 = @workflow.steps.create!(name: "Step B", step_type: "prompt", body: "B", position: 2)

        post reorder_assistant_api_project_workflow_steps_path(project_id: @project, workflow_id: @workflow),
             params: { steps: [{ id: step1.id, position: 2 }, { id: step2.id, position: 1 }] },
             headers: auth_headers
        assert_response :success
        assert_equal 2, step1.reload.position
        assert_equal 1, step2.reload.position
      end

      test "DELETE destroy removes step" do
        step = @workflow.steps.create!(name: "Delete Me", step_type: "prompt", body: "x", position: 99)
        assert_difference "Step.count", -1 do
          delete assistant_api_project_workflow_step_path(project_id: @project, workflow_id: @workflow, id: step), headers: auth_headers
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
