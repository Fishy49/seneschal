module ComponentsHelper
  CHIP_TONES = {
    neutral: "bg-surface-input text-content-muted",
    accent: "bg-accent/15 text-accent",
    ok: "bg-success/15 text-success",
    warn: "bg-warning/15 text-warning",
    danger: "bg-danger/15 text-danger"
  }.freeze

  AVATAR_SIZES = {
    xs: "w-5 h-5 text-[0.5625rem]",
    sm: "w-6 h-6 text-[0.625rem]",
    md: "w-8 h-8 text-[0.75rem]"
  }.freeze

  # "passed" is the run-step flavour of "completed"; both read as success.
  STATUS_DOT_CLASSES = {
    "running" => "bg-info",
    "streaming" => "bg-info",
    "completed" => "bg-success",
    "passed" => "bg-success",
    "failed" => "bg-danger",
    "awaiting_approval" => "bg-warning",
    "waiting_for_tokens" => "bg-warning"
  }.freeze

  # Timeline node tints for the run steps list. The node carries the step's
  # status, so there is no separate status dot on the row.
  STEP_NODE_CLASSES = {
    "completed" => "node-tint-success text-success",
    "passed" => "node-tint-success text-success",
    "failed" => "node-tint-danger text-danger",
    "running" => "node-tint-info text-info animate-pulse",
    "retrying" => "node-tint-info text-info animate-pulse",
    "awaiting_approval" => "node-tint-warning text-warning",
    "waiting_for_tokens" => "node-tint-warning text-warning"
  }.freeze

  def step_node_classes(status)
    STEP_NODE_CLASSES.fetch(status.to_s, "node-tint-muted text-content-muted")
  end

  def chip_tone_classes(tone)
    CHIP_TONES.fetch(tone.to_sym, CHIP_TONES[:neutral])
  end

  def status_dot(status)
    color = STATUS_DOT_CLASSES[status.to_s] || "bg-content-muted"
    pulse = status.to_s.in?(["running", "streaming"]) ? " animate-pulse" : ""
    content_tag :span, "", class: "inline-block w-2 h-2 rounded-full shrink-0 #{color}#{pulse}", title: status.to_s.tr("_", " ")
  end

  # Initials circle. Mirrors the client-side rule in presence_controller.js so
  # a server-rendered avatar and a live presence chip agree on the letters.
  def avatar_for(user, size: :sm)
    return nil unless user

    avatar_for_email(user.email, size: size)
  end

  # Presence rosters carry emails, not user records.
  def avatar_for_email(email, size: :sm)
    return nil if email.blank?

    classes = "inline-flex items-center justify-center rounded-full bg-surface-input border border-edge " \
              "font-semibold text-content-muted #{AVATAR_SIZES.fetch(size.to_sym, AVATAR_SIZES[:sm])}"
    content_tag :span, user_initials(email), title: email, class: classes
  end

  def user_initials(email)
    local = email.to_s.split("@").first.to_s
    parts = local.split(/[._-]+/).reject(&:empty?)
    letters = parts.size > 1 ? "#{parts[0][0]}#{parts[1][0]}" : local[0, 2].to_s
    letters.upcase
  end
end
