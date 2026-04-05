require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "GET register renders form" do
    get register_path
    assert_response :success
    assert_select "h2", "Create Account"
  end

  test "POST register creates user and signs in" do
    assert_difference "User.count", 1 do
      post register_path, params: {
        user: { email: "new@test.com", password: "password", password_confirmation: "password" }
      }
    end
    assert_redirected_to root_path
  end

  test "POST register with mismatched passwords" do
    assert_no_difference "User.count" do
      post register_path, params: {
        user: { email: "new@test.com", password: "password", password_confirmation: "different" }
      }
    end
    assert_response :unprocessable_content
  end

  test "POST register with duplicate email" do
    assert_no_difference "User.count" do
      post register_path, params: {
        user: { email: users(:admin).email, password: "password", password_confirmation: "password" }
      }
    end
    assert_response :unprocessable_content
  end

  test "POST register with blank email" do
    assert_no_difference "User.count" do
      post register_path, params: {
        user: { email: "", password: "password", password_confirmation: "password" }
      }
    end
    assert_response :unprocessable_content
  end
end
