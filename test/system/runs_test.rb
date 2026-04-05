require "application_system_test_case"

class RunsTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
  end

  test "list runs" do
    visit runs_path
    assert_text "Deploy Pipeline"
    assert_text "Seneschal"
  end

  test "view run details" do
    visit run_path(runs(:completed_run))
    assert_text "Run ##{runs(:completed_run).id}"
    assert_text "Plan Feature"
  end

  test "view run with usage stats" do
    visit run_path(runs(:completed_run))
    assert_text "$0.05"
    assert_text "5 turns"
  end

  test "filter runs by status" do
    visit runs_path
    select "Failed", from: "status"

    assert_text "Deploy Pipeline"
  end
end
