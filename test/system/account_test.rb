require "application_system_test_case"

class AccountTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
  end

  test "view account page" do
    visit account_path
    assert_text "Account"
    assert_selector "input[value='admin@test.com']"
  end

  test "update email" do
    visit account_path
    fill_in "Email", with: "updated@test.com"
    click_on "Save Changes"

    assert_text "Account updated"
  end

  test "navigate to account from sidebar" do
    visit root_path
    click_on "admin@test.com"

    assert_current_path account_path
  end
end
