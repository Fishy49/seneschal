require "test_helper"

class StepTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists templates" do
    get step_templates_path
    assert_response :success
    assert_select "h2", text: "Standard Plan Step"
    assert_select "h2", text: "Git Checkout Main"
  end

  test "DELETE destroy removes template" do
    assert_difference "StepTemplate.count", -1 do
      delete step_template_path(step_templates(:command_template))
    end
    assert_redirected_to step_templates_path
  end

  test "GET show summarises the captured configuration" do
    template = StepTemplate.create!(name: "Shown", step_type: "ci_check", timeout: 900, max_retries: 2,
                                    description: "Waits for the build",
                                    config: { "produces" => ["build_status"], "consumes" => ["pr_number"] })

    get step_template_path(template)
    assert_response :success
    assert_select "h1", text: "Shown"
    assert_select "p", text: "Waits for the build"
    assert_select "span", text: "build_status"
    assert_select "span", text: "pr_number"
  end

  test "GET edit offers only name and description" do
    template = StepTemplate.create!(name: "Editable", step_type: "command", body: "echo hi", timeout: 60, max_retries: 0)

    get edit_step_template_path(template)
    assert_select "input[name=?]", "step_template[name]"
    assert_select "textarea[name=?]", "step_template[description]"
    assert_select "input[name=?]", "step_template[timeout]", count: 0
  end

  test "PATCH update renames and describes" do
    template = StepTemplate.create!(name: "Old name", step_type: "command", body: "echo hi", timeout: 60, max_retries: 0)

    patch step_template_path(template), params: {
      step_template: { name: "New name", description: "Now explained" }
    }
    assert_redirected_to step_template_path(template)

    template.reload
    assert_equal "New name", template.name
    assert_equal "Now explained", template.description
  end

  test "PATCH update rejects a blank name" do
    template = StepTemplate.create!(name: "Keeps its name", step_type: "command", body: "echo hi", timeout: 60, max_retries: 0)

    patch step_template_path(template), params: { step_template: { name: "" } }
    assert_response :unprocessable_content
    assert_equal "Keeps its name", template.reload.name
  end

  test "the index describes each template" do
    StepTemplate.create!(name: "Described", step_type: "command", body: "echo hi", timeout: 60, max_retries: 0,
                         description: "Does a thing")
    get step_templates_path
    assert_select "p", text: "Does a thing"
  end
end
