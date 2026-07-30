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

  test "typing searches and arrow-enter jumps" do
    visit root_path
    find("body").send_keys([:control, "k"])

    box = find("[data-command-palette-target='description']")
    box.fill_in with: "Deploy Pip"
    assert_selector "[data-command-palette-target='results'] button", text: /Deploy Pipeline/

    box.send_keys(:arrow_down)
    box.send_keys(:enter)
    assert_current_path project_workflow_path(projects(:seneschal), workflows(:deploy))
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

    assert_selector "h1", text: "Try the launch bar · run 1", normalize_ws: true
    assert_equal "Try the launch bar", PipelineTask.last.title
  end

  test "the launch bar reports validation errors inline" do
    visit runs_path
    find("body").send_keys([:control, "k"])

    find("[data-command-palette-target='submit']").click
    assert_text "Describe what you want run."
    assert_selector "[data-command-palette-target='description']", visible: true
  end

  test "choosing a workflow shows what it costs and what it can touch" do
    visit runs_path
    find("body").send_keys([:control, "k"])

    select "Seneschal", from: "Project"
    select "Deploy Pipeline", from: "Workflow"

    assert_selector "[data-command-palette-target='summary']", visible: true
  end

  test "the composer link carries what has been typed" do
    visit runs_path
    find("body").send_keys([:control, "k"])

    fill_in "What should Claude do?", with: "Add rate limiting"
    select "Seneschal", from: "Project"

    link = find("[data-command-palette-target='composer']")
    assert_includes link[:href], "description=Add+rate+limiting"
    assert_includes link[:href], "project_id=#{projects(:seneschal).id}"
  end
end
