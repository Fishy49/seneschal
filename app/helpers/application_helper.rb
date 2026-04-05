module ApplicationHelper
  BADGE_BASE = "inline-block px-2 py-0.5 rounded-full text-xs font-semibold uppercase tracking-wide"

  STATUS_CLASSES = {
    "pending"   => "bg-surface-input text-content-muted",
    "queued"    => "bg-info/15 text-info",
    "running"   => "bg-accent/15 text-accent",
    "completed" => "bg-success/15 text-success",
    "passed"    => "bg-success/15 text-success",
    "failed"    => "bg-danger/15 text-danger",
    "stopped"   => "bg-warning/15 text-warning",
    "retrying"  => "bg-warning/15 text-warning",
    "skipped"   => "bg-surface-input text-content-muted",
    "draft"     => "bg-surface-input text-content-muted",
    "ready"     => "bg-info/15 text-info"
  }.freeze

  TYPE_CLASSES = {
    "skill"    => "bg-accent/15 text-accent",
    "script"   => "bg-success/15 text-success",
    "command"  => "bg-info/15 text-info",
    "ci_check" => "bg-warning/15 text-warning",
    "feature"  => "bg-accent/15 text-accent",
    "bugfix"   => "bg-danger/15 text-danger",
    "chore"    => "bg-warning/15 text-warning"
  }.freeze

  def status_badge(status)
    classes = "#{BADGE_BASE} #{STATUS_CLASSES[status] || STATUS_CLASSES['pending']}"
    if status.in?(%w[running retrying])
      dot = content_tag(:span, "", class: "inline-block w-1.5 h-1.5 rounded-full bg-current animate-pulse mr-1 align-middle")
      content_tag(:span, dot + status, class: "#{classes} flex items-center gap-0")
    else
      content_tag(:span, status, class: classes)
    end
  end

  def type_badge(type)
    content_tag :span, type, class: "#{BADGE_BASE} #{TYPE_CLASSES[type] || 'bg-surface-input text-content-muted'}"
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
    time_ago_in_words(time) + " ago"
  end
end
