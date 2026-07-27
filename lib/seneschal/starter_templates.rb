module Seneschal
  # The workflows a fresh install starts from. Each one is a real
  # `seneschal_workflow_export` payload, so "use this template" is the same
  # code path as importing a workflow somebody exported.
  module StarterTemplates
    ROOT = Rails.root.join("lib/seneschal/starter_templates")

    Template = Data.define(:key, :name, :description, :teaches) do
      def path = ROOT.join("#{key}.json")
      def payload = JSON.parse(path.read)
      def step_types = payload.dig("seneschal_workflow_export", "workflow", "steps").map { |s| s["step_type"] }
    end

    ALL = [
      Template.new(
        key: "classic_feature",
        name: "Plan, build, review, ship",
        description: "Plan the work, implement it, review the diff, open a pull request, wait for CI.",
        teaches: "the core loop"
      ),
      Template.new(
        key: "bugfix",
        name: "Diagnose, then fix",
        description: "Reproduce and understand the bug before changing anything, then fix its cause.",
        teaches: "diagnosis first"
      ),
      Template.new(
        key: "guarded_refactor",
        name: "Refactor with a checkpoint",
        description: "Plans the refactor, pauses for a person to approve the plan, then carries it out.",
        teaches: "approval gates"
      ),
      Template.new(
        key: "docs_pass",
        name: "Documentation pass",
        description: "Finds what the docs get wrong and rewrites them. No CI, since nothing executable changes.",
        teaches: "a light pipeline"
      ),
      Template.new(
        key: "scheduled_maintenance",
        name: "Dependency update",
        description: "Updates dependencies and opens a pull request. Pair it with a task set to run on a schedule.",
        teaches: "scheduling"
      )
    ].freeze

    def self.list = ALL

    def self.find(key) = ALL.find { |template| template.key == key.to_s }
  end
end
