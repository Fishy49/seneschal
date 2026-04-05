class RunStep < ApplicationRecord
  belongs_to :run
  belongs_to :step

  STATUSES = ["pending", "queued", "running", "passed", "failed", "retrying", "skipped"].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :attempt, numericality: { only_integer: true, greater_than: 0 }

  def usage_stats
    return nil unless stream_log.is_a?(Array)

    result = stream_log.find { |e| e["type"] == "result" }
    return nil unless result

    usage = result["usage"] || {}
    {
      cost_usd: result["total_cost_usd"].to_f,
      input_tokens: usage["input_tokens"].to_i,
      output_tokens: usage["output_tokens"].to_i,
      cache_read_tokens: usage["cache_read_input_tokens"].to_i,
      cache_creation_tokens: usage["cache_creation_input_tokens"].to_i,
      duration_ms: result["duration_ms"].to_i,
      num_turns: result["num_turns"].to_i
    }
  end
end
