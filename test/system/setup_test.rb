require "application_system_test_case"

class SetupTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
  end

  test "view setup page" do
    visit setup_path
    assert_text "Claude CLI"
    assert_text "GitHub CLI"
  end

  test "setup page shows integration status" do
    visit setup_path
    assert_text "claude 1.0.0"
    assert_text "gh version 2.0.0"
  end

  test "setup redirects when integrations missing" do
    Setting.destroy_all
    visit root_path
    assert_current_path setup_path
  end
end
