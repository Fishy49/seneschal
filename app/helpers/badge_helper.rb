module BadgeHelper
  BADGE_BASE = "inline-block px-2 py-0.5 rounded-full text-xs font-semibold uppercase tracking-wide".freeze

  STATUS_CLASSES = {
    "pending" => "bg-surface-input text-content-muted",
    "queued" => "bg-info/15 text-info",
    "running" => "bg-accent/15 text-accent",
    "awaiting_approval" => "bg-warning/15 text-warning",
    "waiting_for_tokens" => "bg-warning/15 text-warning",
    "completed" => "bg-success/15 text-success",
    "passed" => "bg-success/15 text-success",
    "failed" => "bg-danger/15 text-danger",
    "stopped" => "bg-warning/15 text-warning",
    "retrying" => "bg-warning/15 text-warning",
    "skipped" => "bg-surface-input text-content-muted",
    "draft" => "bg-surface-input text-content-muted",
    "ready" => "bg-info/15 text-info"
  }.freeze

  TYPE_CLASSES = {
    "skill" => "bg-accent/15 text-accent",
    "prompt" => "bg-accent/15 text-accent",
    "script" => "bg-success/15 text-success",
    "command" => "bg-info/15 text-info",
    "ci_check" => "bg-warning/15 text-warning",
    "context_fetch" => "bg-info/15 text-info",
    "pr" => "bg-success/15 text-success",
    "feature" => "bg-accent/15 text-accent",
    "bugfix" => "bg-danger/15 text-danger",
    "chore" => "bg-warning/15 text-warning"
  }.freeze

  # Plain-language gloss per value. This is the badge legend: it lives on the
  # badge itself rather than on a page nobody would go looking for.
  STATUS_TOOLTIPS = {
    "pending" => "Not started yet",
    "queued" => "Waiting for a free worker",
    "running" => "Working on it now",
    "awaiting_approval" => "Paused until a person approves this step",
    "waiting_for_tokens" => "Paused until the model's rate limit resets",
    "completed" => "Finished, every step passed",
    "passed" => "This step finished successfully",
    "failed" => "Stopped on an error",
    "stopped" => "Cancelled by a person",
    "retrying" => "Failed once, trying again",
    "skipped" => "Not run",
    "draft" => "Saved but never launched",
    "ready" => "Ready to launch"
  }.freeze

  TYPE_TOOLTIPS = {
    "skill" => "Runs an AI agent with a reusable SKILL.md",
    "prompt" => "Sends one prompt to the model, no tools",
    "script" => "Runs a shell script in the checkout",
    "command" => "Runs a shell command in the checkout",
    "ci_check" => "Waits for GitHub checks",
    "context_fetch" => "Pulls data in before the next step",
    "pr" => "Opens a pull request",
    "self_review" => "Has the agent review its own diff",
    "feature" => "New work",
    "bugfix" => "Fixing something broken",
    "chore" => "Maintenance"
  }.freeze

  def status_badge(status)
    classes = "#{BADGE_BASE} #{STATUS_CLASSES[status] || STATUS_CLASSES["pending"]}"
    display = status.to_s.tr("_", " ")
    title = STATUS_TOOLTIPS[status]
    if status.in?(["running", "retrying", "waiting_for_tokens"])
      dot = content_tag(:span, "", class: "inline-block w-1.5 h-1.5 rounded-full bg-current animate-pulse mr-1 align-middle")
      content_tag(:span, dot + display, class: "#{classes} flex items-center gap-0", title: title)
    else
      content_tag(:span, display, class: classes, title: title)
    end
  end

  def type_badge(type)
    classes = "#{BADGE_BASE} #{TYPE_CLASSES[type] || "bg-surface-input text-content-muted"}"
    content_tag :span, type, class: classes, title: TYPE_TOOLTIPS[type]
  end
end
