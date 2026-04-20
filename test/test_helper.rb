ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Lightweight stub/mock helpers (Minitest 6 no longer ships Minitest::Mock).
class Object
  def stub(name, val_or_callable, &)
    metaclass = singleton_class
    original = metaclass.instance_method(name) if metaclass.method_defined?(name) || metaclass.private_method_defined?(name)
    if val_or_callable.respond_to?(:call)
      metaclass.send(:define_method, name) { |*a, **k, &b| val_or_callable.call(*a, **k, &b) }
    else
      metaclass.send(:define_method, name) { |*_a, **_k, &_b| val_or_callable }
    end
    yield
  ensure
    begin
      metaclass.send(:remove_method, name)
    rescue StandardError
      nil
    end
    metaclass.send(:define_method, name, original) if original
  end
end

module Minitest
  class Mock
    def initialize
      @expected = Hash.new { |h, k| h[k] = [] }
    end

    def expect(name, retval, args = [], **kwargs)
      @expected[name] << { retval: retval, args: args, kwargs: kwargs }
      self
    end

    def method_missing(name, *args, **kwargs, &)
      if (calls = @expected[name]) && calls.any?
        calls.shift[:retval]
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      @expected.key?(name) || super
    end

    def verify # rubocop:disable Naming/PredicateMethod
      true
    end
  end
end

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

  def assistant_sign_in(conversation)
    @headers = { "Authorization" => "Bearer #{conversation.turbo_token}" }
  end
end
