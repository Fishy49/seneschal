require "test_helper"

class NotifyJobTest < ActiveJob::TestCase
  # Minimal Net::HTTP stand-in: records what would have gone over the wire.
  class FakeHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout
    attr_reader :requests

    def initialize(raise_with: nil)
      @requests = []
      @raise_with = raise_with
    end

    def request(req)
      raise @raise_with if @raise_with

      @requests << req
      Struct.new(:code).new("200")
    end
  end

  setup do
    Setting["webhook_url"] = "https://example.test/hooks/seneschal"
    Setting["app_base_url"] = "https://seneschal.internal"
    @run = runs(:completed_run)
  end

  # No HTTP-stubbing gem in this project, and minitest 6 no longer ships
  # minitest/mock, so swap Net::HTTP.new for the duration of the block.
  def with_http(http)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_args| http }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def capture_post(&)
    http = FakeHttp.new
    with_http(http, &)
    http
  end

  test "posts a JSON payload describing the run" do
    http = capture_post { NotifyJob.perform_now("run.completed", @run.id) }

    assert_equal 1, http.requests.size
    request = http.requests.first
    assert_equal "application/json", request["Content-Type"]

    body = JSON.parse(request.body)
    assert_equal "run.completed", body["event"]
    assert_equal @run.id, body["run"]["id"]
    assert_equal "completed", body["run"]["status"]
    assert_equal "https://seneschal.internal/runs/#{@run.id}", body["run"]["url"]
    assert_equal @run.pipeline_task.title, body["run"]["task_title"]
    assert_equal "Seneschal", body["run"]["project"]
    assert_equal "Deploy Pipeline", body["run"]["workflow"]
    assert_equal @run.started_by_label, body["run"]["started_by"]
    assert body["timestamp"].present?
  end

  test "omits the url when no base url is configured" do
    Setting["app_base_url"] = ""
    http = capture_post { NotifyJob.perform_now("run.failed", @run.id) }
    assert_nil JSON.parse(http.requests.first.body)["run"]["url"]
  end

  test "sets both timeouts and honours the scheme" do
    http = FakeHttp.new
    with_http(http) { NotifyJob.perform_now("run.completed", @run.id) }

    assert http.use_ssl
    assert_equal NotifyJob::OPEN_TIMEOUT, http.open_timeout
    assert_equal NotifyJob::READ_TIMEOUT, http.read_timeout
  end

  test "does nothing when no webhook url is configured" do
    Setting["webhook_url"] = ""
    http = capture_post { NotifyJob.perform_now("run.completed", @run.id) }
    assert_empty http.requests
  end

  test "swallows delivery errors instead of failing the job" do
    http = FakeHttp.new(raise_with: Errno::ECONNREFUSED)
    with_http(http) do
      assert_nothing_raised { NotifyJob.perform_now("run.failed", @run.id) }
    end
  end

  test "swallows a malformed webhook url" do
    Setting["webhook_url"] = "not a url at all"
    assert_nothing_raised { NotifyJob.perform_now("run.failed", @run.id) }
  end

  test "is a no-op for a run that no longer exists" do
    http = capture_post { NotifyJob.perform_now("run.failed", -1) }
    assert_empty http.requests
  end

  test "configured? follows the webhook setting" do
    assert NotifyJob.configured?
    Setting["webhook_url"] = ""
    assert_not NotifyJob.configured?
  end
end
