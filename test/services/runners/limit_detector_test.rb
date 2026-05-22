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
      assert_equal Time.zone.at(1716400200), out[:reset_at]
    end
  end
end
