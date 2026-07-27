require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index renders dashboard" do
    get root_path
    assert_response :success
    assert_select "h1", "Home"
  end

  test "sidebar badges the number of runs awaiting approval" do
    get root_path
    assert_response :success
    assert_select "a[href=?] span[title*=?]", runs_path, "awaiting approval", text: "1"
  end

  test "sidebar has no badge when nothing is parked" do
    Run.awaiting_approval.find_each { |r| r.update!(status: "completed") }
    get root_path
    assert_response :success
    assert_select "a[href=?] span[title*=?]", runs_path, "awaiting approval", false
  end

  test "loads highlight.js and its theme from local assets" do
    get root_path
    assert_response :success
    assert_no_match(/cdnjs\.cloudflare\.com/, response.body)
    assert_select "script[src*=?]", "highlight"
    assert_select "link#hljs-theme[href*=?]", "highlight-github-dark"
  end

  test "redirects to login when not authenticated" do
    delete logout_path
    get root_path
    assert_redirected_to login_path
  end

  test "shows active runs" do
    get root_path
    assert_response :success
    assert_select "#dashboard_active a[href=?]", run_path(runs(:active_run))
  end

  test "the runs card carries one active section and one recent section" do
    get root_path
    assert_response :success
    assert_select "#dashboard_active"
    assert_select "h2", text: "Runs"
    assert_select "h3", text: "Active"
    assert_select "h3", text: "Recent"
  end

  test "run rows credit whoever launched them" do
    run = runs(:completed_run)
    run.update!(started_by: users(:other))
    get root_path
    assert_select "span[title=?]", users(:other).email
  end

  test "each project offers a launch button that preselects it" do
    get root_path
    assert_select "button[data-action=?][data-command-palette-project-param=?]",
                  "command-palette#openWithProject", projects(:seneschal).id.to_s
  end

  test "Home leads with a launch button" do
    get root_path
    assert_select "h1", "Home"
    assert_select "button[data-action=?]", "command-palette#open"
  end

  test "surfaces runs awaiting approval in their own section" do
    run = runs(:awaiting_run)
    get root_path
    assert_response :success
    assert_select "#dashboard_awaiting" do
      assert_select "a[href=?]", run_path(run)
    end
    assert_match(/Needs you/, response.body)
  end

  test "awaiting runs are not duplicated into active runs" do
    run = runs(:awaiting_run)
    get root_path
    assert_response :success
    assert_select "#dashboard_active a[href=?]", run_path(run), false
  end

  test "needs-you section is absent when nothing is parked" do
    Run.awaiting_approval.find_each { |r| r.update!(status: "completed") }
    get root_path
    assert_response :success
    assert_no_match(/Needs you/, response.body)
  end

  test "shows projects" do
    get root_path
    assert_response :success
  end

  test "dashboard sidebar lists project groups" do
    get root_path
    assert_response :success
    assert_match "Frontend", response.body
    assert_match project_path(projects(:seneschal)), response.body
  end

  # D.4: the checklist teaches a new member and then gets out of the way.
  test "a member who has never launched sees the checklist" do
    sign_in users(:other)
    get root_path

    assert_select "h2", text: "Getting started"
    assert_select "li", text: /Connect your accounts/
    assert_select "li", text: /Launch your first run/
  end

  test "the checklist ticks off what is already done" do
    sign_in users(:other)
    users(:other).user_credentials.create!(kind: "github_token", value: "ghp_example")
    get root_path

    assert_select "li", text: /Connect your accounts/ do
      assert_select "div.line-through"
    end
    # A project exists in the fixtures, so that item is done too.
    assert_select "li a[href=?]", projects_path, text: "Browse projects"
  end

  test "the checklist offers to add a project when there are none" do
    sign_in users(:other)
    Run.destroy_all
    PipelineTask.destroy_all
    Project.destroy_all

    get root_path
    assert_select "li a[href=?]", new_project_path, text: "Add a project"
  end

  test "the checklist disappears once you have launched something" do
    sign_in users(:other)
    runs(:completed_run).update!(started_by: users(:other))

    get root_path
    assert_select "h2", text: "Getting started", count: 0
  end
end
