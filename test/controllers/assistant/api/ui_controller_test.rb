require "test_helper"

module Assistant
  module Api
    class UiControllerTest < ActionDispatch::IntegrationTest
      setup do
        @conversation = assistant_conversations(:admin_conversation)
        @token = @conversation.turbo_token
      end

      test "POST ask_choices returns 401 without token" do
        post assistant_api_ui_ask_choices_path,
             params: { prompt: "Pick one", choices: [{ label: "A", value: "a" }] },
             as: :json
        assert_response :unauthorized
      end

      test "POST ask_choices creates assistant message with choices" do
        assert_difference "AssistantMessage.count", 1 do
          post assistant_api_ui_ask_choices_path,
               params: { prompt: "Pick one", choices: [{ label: "A", value: "a" }, { label: "B", value: "b" }] },
               headers: auth_headers,
               as: :json
        end
        assert_response :created
        msg = AssistantMessage.last
        assert_equal "assistant", msg.role
        assert_equal "Pick one", msg.content
        assert_equal 2, msg.choices_array.size
      end

      test "POST ask_choices sets conversation status to waiting_user" do
        post assistant_api_ui_ask_choices_path,
             params: { prompt: "Pick one", choices: [{ label: "A", value: "a" }] },
             headers: auth_headers,
             as: :json
        assert_equal "waiting_user", @conversation.reload.status
      end

      test "POST ask_text creates plain assistant message" do
        assert_difference "AssistantMessage.count", 1 do
          post assistant_api_ui_ask_text_path,
               params: { prompt: "What is your goal?" },
               headers: auth_headers,
               as: :json
        end
        assert_response :created
        msg = AssistantMessage.last
        assert_equal "assistant", msg.role
        assert_empty msg.choices_array
      end

      test "POST ask_text sets conversation status to waiting_user" do
        post assistant_api_ui_ask_text_path,
             params: { prompt: "What is your goal?" },
             headers: auth_headers,
             as: :json
        assert_equal "waiting_user", @conversation.reload.status
      end

      test "POST navigate broadcasts stream" do
        Turbo::StreamsChannel.stub(:broadcast_stream_to, true) do
          post assistant_api_ui_navigate_path,
               params: { path: "/projects/1" },
               headers: auth_headers,
               as: :json
          assert_response :success
        end
      end

      private

      def auth_headers
        { "Authorization" => "Bearer #{@token}" }
      end
    end
  end
end
