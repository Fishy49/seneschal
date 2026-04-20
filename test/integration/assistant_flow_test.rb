require "test_helper"

class AssistantFlowTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "bubble renders for signed in user" do
    get root_path
    assert_response :success
    assert_select "[data-controller='assistant']"
  end

  test "bubble hidden when signed out" do
    sign_out
    get login_path
    assert_response :success
    assert_select "[data-controller='assistant']", count: 0
  end

  test "POST assistant_conversation creates conversation and returns turbo stream" do
    assert_difference "AssistantConversation.count", 1 do
      post assistant_conversation_path,
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  test "full turn round trip with stubbed orchestrator" do
    conv = assistant_conversations(:admin_conversation)

    stub_orchestrator_for_test do
      assert_difference "AssistantMessage.count", 1 do
        post assistant_conversation_assistant_messages_path,
             params: { content: "Create a workflow" }
      end
    end

    assert_equal "thinking", conv.reload.status
    assert_enqueued_with(job: RunAssistantTurnJob)
  end

  test "workflow creation via API" do
    conv = assistant_conversations(:admin_conversation)
    token = conv.turbo_token
    project = projects(:seneschal)

    assert_difference "Workflow.count", 1 do
      post assistant_api_project_workflows_path(project_id: project),
           params: { name: "Test Workflow", trigger_type: "manual" },
           headers: { "Authorization" => "Bearer #{token}" }
      assert_response :created
    end

    workflow = Workflow.last

    assert_difference "Step.count", 2 do
      post assistant_api_project_workflow_steps_path(project_id: project, workflow_id: workflow),
           params: { name: "Step 1", step_type: "prompt", body: "Do thing A" },
           headers: { "Authorization" => "Bearer #{token}" }
      post assistant_api_project_workflow_steps_path(project_id: project, workflow_id: workflow),
           params: { name: "Step 2", step_type: "prompt", body: "Do thing B" },
           headers: { "Authorization" => "Bearer #{token}" }
    end

    assert_equal 2, workflow.reload.steps.count

    Turbo::StreamsChannel.stub(:broadcast_stream_to, true) do
      post assistant_api_ui_navigate_path,
           params: { path: "/projects/#{project.id}/workflows/#{workflow.id}" },
           headers: { "Authorization" => "Bearer #{token}" }
      assert_response :success
    end
  end

  private

  def stub_orchestrator_for_test(&block)
    mock_orch = Object.new
    mock_orch.define_singleton_method(:run) { |_msg, &_blk| { output: "done", events: [], claude_session_id: nil } }
    AssistantOrchestrator.stub(:new, ->(_c) { mock_orch }, &block)
  end
end
