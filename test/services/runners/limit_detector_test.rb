require "test_helper"

module Runners
  class LimitDetectorTest < ActiveSupport::TestCase
    def result_with(stderr: "", stdout: "", stream_events: nil)
      Runners::Result.new(exit_code: 1, stdout: stdout, stderr: stderr, stream_events: stream_events)
    end

    test "no limit text returns limit_hit false" do
      r = result_with(stderr: "something else broke")
      out = LimitDetector.detect(r)
      assert_equal false, out[:limit_hit]
      assert_nil out[:reset_at]
    end

    test "matches the usage-limit-reached phrase" do
      r = result_with(stderr: "Claude AI usage limit reached. resets at 2026-05-22T18:30:00Z")
      out = LimitDetector.detect(r)
      assert out[:limit_hit]
      assert_equal Time.zone.parse("2026-05-22T18:30:00Z"), out[:reset_at]
    end

    test "matches rate limit text without timestamp" do
      r = result_with(stdout: "Rate limit exceeded. try again later.")
      out = LimitDetector.detect(r)
      assert out[:limit_hit]
      assert_nil out[:reset_at]
    end

    test "parses relative reset time" do
      freeze_time = Time.zone.parse("2026-05-22T12:00:00Z")
      travel_to freeze_time do
        r = result_with(stderr: "5-hour limit reached, resets in 2h 30m")
        out = LimitDetector.detect(r)
        assert out[:limit_hit]
        assert_equal freeze_time + (2 * 3600) + (30 * 60), out[:reset_at]
      end
    end

    test "scans stream_events error messages" do
      events = [{ "type" => "error", "message" => "session limit hit; please wait" }]
      r = result_with(stream_events: events)
      out = LimitDetector.detect(r)
      assert out[:limit_hit]
    end

    test "parses epoch reset timestamp" do
      r = result_with(stderr: "usage limit reached, resets at 1716400200")
      out = LimitDetector.detect(r)
      assert out[:limit_hit]
      assert_equal Time.zone.at(1_716_400_200), out[:reset_at]
    end

    test "does not false-positive on incidental mentions of 'rate limit'" do
      [
        "ArgumentError: configure a rate limit of at most 100/sec",
        "test 'enforces rate limit' failed: expected 429 got 200",
        "# we have a rate limit budget per minute"
      ].each do |stderr|
        r = result_with(stderr: stderr)
        out = LimitDetector.detect(r)
        assert_equal false, out[:limit_hit], "expected #{stderr.inspect} not to trip"
      end
    end

    test "matches the CLI 'out of extra usage' banner and parses bare clock-tz reset" do
      freeze_time = Time.use_zone("America/Chicago") { Time.zone.parse("2026-05-24 00:00:00") }
      travel_to freeze_time do
        r = result_with(stdout: "You're out of extra usage · resets 2am (America/Chicago)")
        out = LimitDetector.detect(r)
        assert out[:limit_hit]
        expected = Time.use_zone("America/Chicago") { Time.zone.parse("2026-05-24 02:00:00") }
        assert_equal expected, out[:reset_at]
      end
    end

    test "bare clock-tz reset rolls forward when today's occurrence has already passed" do
      freeze_time = Time.use_zone("America/Chicago") { Time.zone.parse("2026-05-24 03:00:00") }
      travel_to freeze_time do
        r = result_with(stdout: "out of usage · resets 2am (America/Chicago)")
        out = LimitDetector.detect(r)
        assert out[:limit_hit]
        expected = Time.use_zone("America/Chicago") { Time.zone.parse("2026-05-25 02:00:00") }
        assert_equal expected, out[:reset_at]
      end
    end

    test "still trips on real rate-limit phrasings" do
      [
        "anthropic.RateLimitError: 429 rate_limit_error",
        "Rate limit exceeded, please retry",
        "rate-limit reached"
      ].each do |stderr|
        r = result_with(stderr: stderr)
        out = LimitDetector.detect(r)
        assert out[:limit_hit], "expected #{stderr.inspect} to trip"
      end
    end
  end
end
