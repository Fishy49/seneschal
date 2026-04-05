ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    fixtures :all
    parallelize(workers: :number_of_processors)
  end
end

# Sign-in helpers for integration tests
ActionDispatch::IntegrationTest.class_eval do
  private

  def sign_in(user, password: "password")
    post login_path, params: { email: user.email, password: password }
    follow_redirect!
  end

  def sign_out
    delete logout_path
    follow_redirect!
  end
end
