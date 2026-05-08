require "application_system_test_case"

class StepFormProducesTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
    @project = projects(:seneschal)
    @workflow = workflows(:deploy)
  end

  test "can add produce via Enter and button" do
    visit edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))

    produces_input = find("[data-produces-input-target='newInput']")
    produces_input.fill_in with: "pr_number"
    produces_input.native.send_keys(:return)

    produces_input.fill_in with: "branch"
    click_on "Add"

    assert_selector "[data-produces-input-target='tagList'] li", text: "pr_number"
    assert_selector "[data-produces-input-target='tagList'] li", text: "branch"

    hidden = find("[data-produces-input-target='hiddenInput']", visible: false)
    assert_equal "pr_number,branch", hidden.value
  end

  test "duplicate produces entry is rejected" do
    visit edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))

    produces_input = find("[data-produces-input-target='newInput']")
    produces_input.fill_in with: "pr_number"
    produces_input.native.send_keys(:return)
    produces_input.fill_in with: "pr_number"
    produces_input.native.send_keys(:return)

    assert_selector "[data-produces-input-target='tagList'] li", count: 1

    hidden = find("[data-produces-input-target='hiddenInput']", visible: false)
    assert_equal "pr_number", hidden.value
  end
end
