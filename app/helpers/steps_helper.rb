module StepsHelper
  # Plain labels; the stored values are unchanged. "script" is absent on
  # purpose - it and "command" are the same behaviour, offered once as Shell.
  TYPE_OPTIONS = [
    ["Skill", "skill"],
    ["Prompt", "prompt"],
    ["Shell", "command"],
    ["Wait for CI", "ci_check"],
    ["Fetch context", "context_fetch"],
    ["Open PR", "pr"],
    ["Self review", "self_review"]
  ].freeze

  TYPE_LABELS = TYPE_OPTIONS.to_h { |label, value| [value, label] }.merge("script" => "Shell").freeze

  MODEL_OPTIONS = [
    ["Opus 4.7", "claude-opus-4-7"],
    ["Sonnet 4.6", "claude-sonnet-4-6"],
    ["Haiku 4.5", "claude-haiku-4-5-20251001"]
  ].freeze

  EFFORT_OPTIONS = [
    ["Low", "low"],
    ["Medium", "medium"],
    ["High", "high"],
    ["Extra high", "xhigh"],
    ["Max", "max"]
  ].freeze

  def step_type_label(step_type)
    TYPE_LABELS.fetch(step_type.to_s, step_type.to_s.tr("_", " "))
  end
end
