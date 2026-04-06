require "application_system_test_case"

class UsersSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
  end

  test "admin sees Users link in sidebar" do
    visit root_path
    assert_link "Users"
  end

  test "non-admin does not see Users link" do
    using_session(:other_user) do
      sign_in_as users(:other)
      visit root_path
      assert_no_link "Users"
    end
  end

  test "list users" do
    visit users_path
    assert_text users(:admin).email
    assert_text users(:other).email
  end

  test "create new user" do
    visit new_user_path
    fill_in "Email", with: "brandnew@test.com"
    click_on "Create User"

    assert_text "brandnew@test.com"
    assert_text "Invite Pending"
  end

  test "invite link shown for pending user" do
    visit users_path
    assert_text users(:invited_user).email
    assert_text "Invite Pending"
  end
end
