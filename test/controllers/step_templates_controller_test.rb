require "test_helper"

class StepTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists templates" do
    get step_templates_path
    assert_response :success
    assert_select "td", text: "Standard Plan Step"
    assert_select "td", text: "Git Checkout Main"
  end

  test "DELETE destroy removes template" do
    assert_difference "StepTemplate.count", -1 do
      delete step_template_path(step_templates(:command_template))
    end
    assert_redirected_to step_templates_path
  end
end
