# The form, button, table and seal recipes every view builds from. Fields or
# buttons built any other way drift the moment the design moves.
module UiKitHelper
  INPUT_CLASSES = "w-full px-3 py-2 bg-surface-input border border-edge rounded-lg " \
                  "text-content text-sm focus:outline-none focus:border-accent".freeze
  LABEL_CLASSES = "block text-sm font-medium text-content-muted mb-1.5".freeze
  HINT_CLASSES = "text-xs text-content-muted mt-1".freeze

  BTN_VARIANTS = {
    primary: "bg-accent text-on-accent border border-transparent hover:bg-accent-hover",
    brass: "bg-brass text-on-brass border border-transparent hover:bg-brass-hover",
    ghost: "bg-transparent text-content-muted border border-edge hover:bg-surface-input hover:text-content",
    quiet: "bg-transparent text-content-muted border border-transparent hover:text-accent",
    danger: "bg-danger text-white border border-transparent hover:bg-danger/85"
  }.freeze

  BTN_SIZES = {
    md: "px-4 py-2 text-sm rounded-lg",
    sm: "px-2.5 py-1 text-[0.8125rem] rounded-lg",
    xs: "px-2 py-0.5 text-xs rounded-md"
  }.freeze

  # Buttons and button-shaped links share one vocabulary: :primary for the
  # page's main action, :brass ONLY for a human decision (approve, seal),
  # :ghost for secondary, :quiet for inline text actions, :danger to destroy.
  def btn_classes(variant = :primary, size: :md, extra: nil)
    ["inline-flex items-center justify-center gap-1.5 font-medium cursor-pointer transition-colors",
     BTN_VARIANTS.fetch(variant.to_sym), BTN_SIZES.fetch(size.to_sym), extra].compact.join(" ")
  end

  def input_classes(extra = nil)
    [INPUT_CLASSES, extra].compact.join(" ")
  end

  def label_classes(extra = nil)
    [LABEL_CLASSES, extra].compact.join(" ")
  end

  def hint_classes(extra = nil)
    [HINT_CLASSES, extra].compact.join(" ")
  end

  # The one table treatment. Density-aware: cells pad with --cell-y so the
  # Compact preference tightens every table at once.
  def th_classes(extra = nil)
    ["text-left px-3 py-[var(--cell-y)] border-b border-edge text-xs font-semibold " \
     "uppercase tracking-wide text-content-muted", extra].compact.join(" ")
  end

  def td_classes(extra = nil)
    ["px-3 py-[var(--cell-y)] border-b border-edge text-sm", extra].compact.join(" ")
  end

  # The seal: Seneschal's mark for human decisions. Draws in currentColor so
  # callers set the tone (almost always text-brass) on a wrapper.
  def seal_mark(size: 16, css: nil)
    content_tag(:svg, viewBox: "0 0 32 32", width: size, height: size,
                      class: ["shrink-0", css].compact.join(" "), "aria-hidden": "true") do
      safe_join([
                  tag.circle(cx: 16, cy: 16, r: 13, fill: "none", stroke: "currentColor",
                             "stroke-width": "3", "stroke-dasharray": "4.2 2.3"),
                  tag.circle(cx: 16, cy: 16, r: 6.5, fill: "none", stroke: "currentColor",
                             "stroke-width": "1.6"),
                  tag.circle(cx: 16, cy: 16, r: 1.8, fill: "currentColor")
                ])
    end
  end
end
