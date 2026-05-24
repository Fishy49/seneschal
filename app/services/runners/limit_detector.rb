module Runners
  # Sniff a Runner::Result for signs that Claude hit a session / usage / rate
  # limit so ExecuteRunJob can park the step instead of failing it.
  #
  # Claude's user-facing limit messages vary by surface (CLI text, SDK
  # exception string, API error JSON) but they all share a few stable
  # substrings: "usage limit", "rate limit", "session limit". When present,
  # the message often includes a reset time — either an ISO-ish timestamp
  # or a phrase like "resets in 4h 23m". We extract whatever we can; the
  # caller falls back to a polling interval when reset_at is nil.
  module LimitDetector
    module_function

    # Each pattern requires both the noun ("rate limit", "usage limit", etc.)
    # AND a verb / state ("reached", "exceeded", "error", ...). The verb gate
    # is what keeps us from false-positive-parking a real failure whose output
    # just *mentions* limits — test names, doc strings, "we have a rate limit
    # of N/sec" log lines. A false positive here is expensive: the parked
    # run will resume → fail with the same output → re-park, burning tokens
    # in a 10-minute loop until MAX_AGE.
    LIMIT_PATTERNS = [
      /usage limit\s+(?:reached|exceeded|hit)/i,
      /rate[\s-]?limit\s+(?:reached|exceeded|error|hit)/i,
      /rate_?limit_?error/i, # anthropic.RateLimitError / "rate_limit_error"
      /session limit\s+(?:reached|exceeded|hit)/i,
      /5[\s-]?hour limit\s+(?:reached|exceeded|hit)/i,
      /quota\s+(?:exceeded|exhausted)/i,
      /too many requests/i,
      /429\s+(?:too many requests|client error)/i,
      /out of (?:extra\s+)?usage/i # CLI banner: "You're out of extra usage · resets 2am (America/Chicago)"
    ].freeze

    # ISO 8601 timestamps the CLI sometimes embeds: "...resets at 2026-05-22T18:30:00Z"
    ISO_RESET = /resets?\s*(?:at\s*)?(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?)/i

    # Epoch seconds variant: "resets at 1716400200"
    EPOCH_RESET = /resets?\s*(?:at\s*)?(\d{10})/i

    # Relative: "resets in 4h 23m" / "try again in 2 hours"
    RELATIVE_RESET = /(?:resets?|try again)\s*in\s*((?:\d+\s*(?:h|hours?|m|mins?|minutes?|s|secs?|seconds?)\s*)+)/i

    # Bare clock-time + named TZ, as the CLI banner uses:
    # "resets 2am (America/Chicago)" / "resets 11:30pm (America/New_York)"
    CLOCK_TZ_RESET = %r{resets?\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)\s*\(([A-Za-z]+/[A-Za-z_]+)\)}i

    # Examine a Result; returns { limit_hit: bool, reset_at: Time|nil, message: String|nil }
    def detect(result)
      haystack = build_haystack(result)
      return { limit_hit: false, reset_at: nil, message: nil } if haystack.blank?

      hit = LIMIT_PATTERNS.any? { |re| haystack.match?(re) }
      return { limit_hit: false, reset_at: nil, message: nil } unless hit

      { limit_hit: true, reset_at: parse_reset_at(haystack), message: first_match_line(haystack) }
    end

    def build_haystack(result)
      parts = [result.stderr.to_s, result.stdout.to_s]
      Array(result.stream_events).each do |ev|
        next unless ev.is_a?(Hash)

        parts << ev["message"].to_s if ev["type"] == "error"
        parts << ev["result"].to_s if ev["type"] == "result" && ev["subtype"].to_s.include?("error")
      end
      parts.compact_blank.join("\n")
    end

    def parse_reset_at(text)
      if (m = text.match(ISO_RESET))
        begin
          return Time.zone.parse(m[1])
        rescue StandardError
          nil
        end
      end
      if (m = text.match(EPOCH_RESET))
        return Time.zone.at(m[1].to_i)
      end

      if (m = text.match(RELATIVE_RESET))
        seconds = relative_to_seconds(m[1])
        return Time.current + seconds if seconds.positive?
      end

      if (m = text.match(CLOCK_TZ_RESET))
        return parse_clock_tz_reset(hour: m[1].to_i, minute: m[2].to_i, meridiem: m[3], tz_name: m[4])
      end
      nil
    end

    # "2am (America/Chicago)" → the next moment in that zone at that hour.
    # If today's occurrence has already passed, advance to tomorrow.
    def parse_clock_tz_reset(hour:, minute:, meridiem:, tz_name:)
      hour24 = hour % 12
      hour24 += 12 if meridiem.casecmp("pm").zero?
      Time.use_zone(tz_name) do
        t = Time.zone.now.change(hour: hour24, min: minute)
        t += 1.day if t <= Time.zone.now
        t
      end
    rescue ArgumentError
      nil
    end

    def relative_to_seconds(str)
      total = 0
      str.scan(/(\d+)\s*([a-z]+)/i) do |num, unit|
        n = num.to_i
        total += case unit.downcase
                 when /^h/ then n * 3600
                 when /^m/ then n * 60
                 when /^s/ then n
                 else 0
                 end
      end
      total
    end

    def first_match_line(text)
      text.each_line do |line|
        return line.strip if LIMIT_PATTERNS.any? { |re| line.match?(re) }
      end
      nil
    end
  end
end
