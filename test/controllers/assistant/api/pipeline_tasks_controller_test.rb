require "test_helper"

module Assistant
  module Api
    class PipelineTasksControllerTest < ActionDispatch::IntegrationTest
      setup do
        @conversation = assistant_conversations(:admin_conversation)
        @token = @conversation.turbo_token
      end

      test "GET index returns 401 without token" do
        get assistant_api_pipeline_tasks_path
        assert_response :unauthorized
      end

      test "GET index lists tasks" do
        get assistant_api_pipeline_tasks_path, headers: auth_headers
        assert_response :success
        data = response.parsed_body
        assert_kind_of Array, data
      end

      test "POST create creates task" do
        project = projects(:seneschal)
        assert_difference "PipelineTask.count", 1 do
          post assistant_api_pipeline_tasks_path,
               params: { title: "New Task", body: "Description", kind: "feature", project_id: project.id },
               headers: auth_headers
        end
        assert_response :created
      end

      test "PATCH update modifies task" do
        task = pipeline_tasks(:ready_task)
        patch assistant_api_pipeline_task_path(task),
              params: { title: "Updated Title" },
              headers: auth_headers
        assert_response :success
        assert_equal "Updated Title", task.reload.title
      end

      test "DELETE destroy removes task" do
        task = pipeline_tasks(:draft_task)
        assert_difference "PipelineTask.count", -1 do
          delete assistant_api_pipeline_task_path(task), headers: auth_headers
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
