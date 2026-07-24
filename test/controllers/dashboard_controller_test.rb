require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index renders dashboard" do
    get root_path
    assert_response :success
    assert_select "h1", /Dashboard/i
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
  end

  test "shows actionable tasks with a launch button" do
    get root_path
    assert_response :success
    assert_select "#dashboard_actionable" do
      assert_select "form[action=?]", execute_pipeline_task_path(pipeline_tasks(:ready_task))
    end
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
end
