module ApplicationHelper
  # Runs are named after the work, not the row. The id stays visible on detail
  # surfaces and in URLs.
  def run_display_name(run)
    return "Manual run ##{run.id}" unless run.pipeline_task

    "#{run.pipeline_task.title} · run #{run.ordinal}"
  end

  # What an in-flight run is doing right now, for list rows. Reads the loaded
  # run_steps rather than querying, so callers must include them.
  def run_progress_text(run)
    current = run.run_steps.find { |rs| rs.status.in?(["running", "awaiting_approval", "waiting_for_tokens"]) }
    current&.step&.name
  end

  # "34 runs · 91% · ~$1.20", dropping any part we have no honest number for.
  # nil for a workflow nobody has run, so callers can say so in words.
  def workflow_stats_line(stats)
    return nil unless stats.run_count.positive?

    parts = [pluralize(stats.run_count, "run")]
    parts << "#{(stats.success_rate * 100).round}% succeeded" if stats.success_rate
    parts << "~#{format_cost(stats.median_cost)}" if stats.median_cost&.positive?
    parts.join(" · ")
  end

  # Plain names for the two runners. A workflow that pins nothing inherits the
  # server default.
  def workflow_engine_label(workflow)
    (workflow.runner_name || Runners.default_name) == "claude_sdk" ? "Advanced SDK" : "Standard"
  end

  # The one line a collapsed step row shows about how it went. nil when there
  # is nothing worth saying, so the row stays a single line.
  def run_step_result_line(run_step, output_vars)
    case run_step.status
    when "awaiting_approval" then "Waiting on a human"
    when "failed" then run_step.error_output.to_s.lines.first&.strip.presence ||
      run_step.output.to_s.lines.first&.strip.presence
    when "passed"
      "Produced #{output_vars.map(&:first).join(", ")}" if output_vars.any?
    when "skipped" then "Skipped"
    end
  end

  def manual_approval_actions(run)
    return unless run.awaiting_approval?

    render partial: "runs/approval_actions", locals: { run: run, run_step: run.awaiting_run_step }
  end

  def format_duration(seconds)
    return "\u2014" unless seconds

    if seconds < 60
      "#{seconds.round(1)}s"
    elsif seconds < 3600
      "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
    else
      "#{(seconds / 3600).floor}h #{((seconds % 3600) / 60).floor}m"
    end
  end

  def time_ago_short(time)
    return "\u2014" unless time

    "#{time_ago_in_words(time)} ago"
  end

  def format_cost(usd)
    return nil unless usd

    usd < 0.01 ? "$#{format("%.4f", usd)}" : "$#{format("%.2f", usd)}"
  end

  def format_tokens(count)
    return nil unless count&.positive?

    count >= 1_000_000 ? "#{(count / 1_000_000.0).round(1)}M" : "#{(count / 1_000.0).round(1)}k"
  end

  ASSET_KIND_ICONS = { "image" => "\u{1F5BC}", "audio" => "\u{1F50A}", "video" => "\u{1F3AC}" }.freeze

  def asset_kind_icon(kind)
    ASSET_KIND_ICONS[kind.to_s] || "\u{1F4CE}"
  end

  # Runs parked on a manual approval gate. Computed per page load; the
  # dashboard's own polling covers the live case.
  def awaiting_approval_count
    Run.awaiting_approval.count
  end

  def usage_stats_bar(stats)
    return nil unless stats

    parts = []
    parts << format_cost(stats[:cost_usd]) if stats[:cost_usd].positive?
    total_tokens = stats[:input_tokens] + stats[:output_tokens] + stats[:cache_read_tokens] + stats[:cache_creation_tokens]
    parts << "#{format_tokens(total_tokens)} tokens" if total_tokens.positive?
    parts << "#{stats[:num_turns]} turns" if stats[:num_turns].positive?
    parts << format_duration(stats[:duration_ms] / 1000.0) if stats[:duration_ms].positive?
    parts.join(" / ")
  end
end
