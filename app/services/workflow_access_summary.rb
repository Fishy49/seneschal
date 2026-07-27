# What a workflow can reach, derived from its steps' existing config so it can
# be shown before anyone launches it. Presentation only - nothing here changes
# what a run is allowed to do.
class WorkflowAccessSummary
  Chip = Struct.new(:label, :tone, :steps, keyword_init: true) do
    def title
      steps.any? ? steps.join(", ") : nil
    end
  end

  # Blank allowed tools inherit the server default, which contains Edit, so a
  # step that names nothing can still write.
  WRITE_TOOLS = ["edit", "write", "notebookedit"].freeze

  def self.for(workflow) = new(workflow).call

  def initialize(workflow)
    @workflow = workflow
    @steps = workflow.steps.to_a
  end

  def call
    chips = []
    chips << Chip.new(label: "danger mode", tone: :danger, steps: []) if @workflow.project&.skip_permissions?
    chips << chip("opens PRs", :warn) { |step| step.step_type == "pr" }
    chips << chip("runs shell", :warn) { |step| step.step_type.in?(["script", "command"]) }
    chips << chip("writes files", :warn) { |step| writes_files?(step) }
    chips << chip("approval gated", :accent, &:manual_approval)
    chips.compact!

    chips.presence || [Chip.new(label: "read-only", tone: :ok, steps: [])]
  end

  private

  def chip(label, tone, &)
    matching = @steps.select(&)
    return nil if matching.empty?

    Chip.new(label: label, tone: tone, steps: matching.map(&:name))
  end

  def writes_files?(step)
    return false unless step.step_type.in?(["skill", "prompt"])

    tools = step.config.is_a?(Hash) ? step.config["allowed_tools"].to_s : ""
    return true if tools.blank?

    tools.downcase.scan(/[a-z]+/).any? { |word| WRITE_TOOLS.include?(word) }
  end
end
