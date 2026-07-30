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

  test "configured? follows either webhook setting" do
    assert NotifyJob.configured?

    Setting["webhook_url"] = ""
    assert_not NotifyJob.configured?

    Setting["slack_webhook_url"] = "https://hooks.slack.com/services/x"
    assert NotifyJob.configured?
  end

  # --- Slack (3.2) ---

  test "posts a Block Kit message when a Slack webhook is configured" do
    Setting["slack_webhook_url"] = "https://hooks.slack.com/services/x"
    http = capture_post { NotifyJob.perform_now("run.awaiting_approval", @run.id) }

    assert_equal 2, http.requests.size, "generic webhook and Slack should both fire"
    slack = JSON.parse(http.requests.last.body)

    assert_match(/Needs approval/, slack["text"])
    types = slack["blocks"].pluck("type")
    assert_equal ["header", "section", "context", "actions"], types
    assert_match(/Needs approval/, slack["blocks"].first["text"]["text"])
    assert_match(/Deploy Pipeline/, slack["blocks"][2]["elements"].first["text"])

    button = slack["blocks"].last["elements"].first
    assert_equal "Review & approve", button["text"]["text"]
    assert_equal "https://seneschal.internal/runs/#{@run.id}", button["url"]
  end

  test "non-approval events get a plain View run button" do
    Setting["slack_webhook_url"] = "https://hooks.slack.com/services/x"
    http = capture_post { NotifyJob.perform_now("run.failed", @run.id) }

    button = JSON.parse(http.requests.last.body)["blocks"].last["elements"].first
    assert_equal "View run", button["text"]["text"]
  end

  test "Slack message omits the button when there is no base url" do
    Setting["slack_webhook_url"] = "https://hooks.slack.com/services/x"
    Setting["app_base_url"] = ""
    http = capture_post { NotifyJob.perform_now("run.completed", @run.id) }

    types = JSON.parse(http.requests.last.body)["blocks"].pluck("type")
    assert_not_includes types, "actions"
  end

  test "Slack posts even when the generic webhook is not configured" do
    Setting["webhook_url"] = ""
    Setting["slack_webhook_url"] = "https://hooks.slack.com/services/x"
    http = capture_post { NotifyJob.perform_now("run.completed", @run.id) }

    assert_equal 1, http.requests.size
    assert JSON.parse(http.requests.first.body).key?("blocks")
  end

  test "a broken generic webhook does not cost the Slack message" do
    Setting["webhook_url"] = "not a url at all"
    Setting["slack_webhook_url"] = "https://hooks.slack.com/services/x"
    http = capture_post { NotifyJob.perform_now("run.completed", @run.id) }

    assert_equal 1, http.requests.size
    assert JSON.parse(http.requests.first.body).key?("blocks")
  end
end
