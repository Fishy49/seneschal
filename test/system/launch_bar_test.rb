require "application_system_test_case"

class LaunchBarTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
  end

  test "Ctrl+K opens the launch bar and Escape closes it" do
    visit root_path
    assert_no_selector "[data-command-palette-target='description']", visible: true

    find("body").send_keys([:control, "k"])
    assert_selector "[data-command-palette-target='description']", visible: true

    find("body").send_keys(:escape)
    assert_no_selector "[data-command-palette-target='description']", visible: true
  end

  test "the sidebar Launch button opens the launch bar" do
    visit root_path
    assert_no_selector "[data-command-palette-target='description']", visible: true

    within("nav") { click_on "Launch" }
    assert_selector "[data-command-palette-target='description']", visible: true
  end

  test "the launch bar starts a run without visiting the task form" do
    visit runs_path
    find("body").send_keys([:control, "k"])

    fill_in "What should Claude do?", with: "Try the launch bar"
    select "Seneschal", from: "Project"
    select "Deploy Pipeline", from: "Workflow"
    find("[data-command-palette-target='submit']").click

    assert_selector "h1", text: /Run #\d+/
    assert_equal "Try the launch bar", PipelineTask.last.title
  end

  test "the launch bar reports validation errors inline" do
    visit runs_path
    find("body").send_keys([:control, "k"])

    find("[data-command-palette-target='submit']").click
    assert_text "Describe what you want run."
    assert_selector "[data-command-palette-target='description']", visible: true
  end
end
