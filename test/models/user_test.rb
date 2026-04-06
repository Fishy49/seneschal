require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid user" do
    user = User.new(email: "new@test.com", password: "password", password_confirmation: "password")
    assert user.valid?
  end

  test "requires email" do
    user = User.new(password: "password")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "requires unique email" do
    user = User.new(email: users(:admin).email, password: "password")
    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "validates email format" do
    user = User.new(email: "not-an-email", password: "password")
    assert_not user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "authenticates with correct password" do
    user = users(:admin)
    assert user.authenticate("password")
  end

  test "rejects wrong password" do
    user = users(:admin)
    assert_not user.authenticate("wrong")
  end

  test "generate_otp_secret! sets a secret" do
    user = users(:admin)
    assert_nil user.otp_secret
    user.generate_otp_secret!
    assert_not_nil user.reload.otp_secret
  end

  test "enable_2fa! sets flag" do
    user = users(:admin)
    user.enable_2fa!
    assert user.reload.otp_required_for_login
  end

  test "disable_2fa! clears secret and flag" do
    user = users(:twofa_user)
    user.disable_2fa!
    user.reload
    assert_nil user.otp_secret
    assert_not user.otp_required_for_login
  end

  test "verify_otp returns false without secret" do
    user = users(:admin)
    assert_not user.verify_otp("123456")
  end

  test "verify_otp validates correct code" do
    user = users(:twofa_user)
    totp = ROTP::TOTP.new(user.otp_secret)
    assert user.verify_otp(totp.now)
  end

  test "verify_otp rejects wrong code" do
    user = users(:twofa_user)
    assert_not user.verify_otp("000000")
  end

  test "otp_provisioning_uri includes email and issuer" do
    user = users(:twofa_user)
    uri = user.otp_provisioning_uri
    assert_includes uri, URI.encode_www_form_component(user.email)
    assert_includes uri, "Seneschal"
  end

  test "admin? returns true for admin users" do
    assert users(:admin).admin?
    assert_not users(:other).admin?
  end

  test "generate_invite_token! sets token" do
    user = users(:other)
    assert_nil user.invite_token
    user.generate_invite_token!
    assert_not_nil user.reload.invite_token
  end

  test "invite_pending? when token present and not accepted" do
    assert users(:invited_user).invite_pending?
    assert_not users(:admin).invite_pending?
  end

  test "accept_invite sets password and clears token" do
    user = users(:invited_user)
    assert user.accept_invite(password: "newpass123", password_confirmation: "newpass123")
    user.reload
    assert_nil user.invite_token
    assert_not_nil user.invite_accepted_at
    assert user.authenticate("newpass123")
  end

  test "accept_invite fails on mismatched passwords" do
    user = users(:invited_user)
    assert_not user.accept_invite(password: "newpass", password_confirmation: "different")
    assert_not_nil user.reload.invite_token
  end

  test "accept_invite fails on blank password" do
    user = users(:invited_user)
    assert_not user.accept_invite(password: "", password_confirmation: "")
    assert_includes user.errors[:password], "can't be blank"
    assert_not_nil user.reload.invite_token
  end

  test "ordered scope sorts by email" do
    emails = User.ordered.pluck(:email)
    assert_equal emails.sort, emails
  end
end
