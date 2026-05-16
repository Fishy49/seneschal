class Step < ApplicationRecord
  belongs_to :workflow, optional: true
  belongs_to :run, optional: true
  belongs_to :skill, optional: true
  has_many :run_steps, dependent: :destroy

  STEP_TYPES = ["skill", "script", "command", "ci_check", "context_fetch", "prompt", "pr", "self_review"].freeze

  validates :name, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }, unless: -> { run_id.present? }
  validates :step_type, presence: true, inclusion: { in: STEP_TYPES }
  validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :timeout, numericality: { only_integer: true, greater_than: 0 }
  validates :skill, presence: true, if: -> { step_type == "skill" }
  validates :body, presence: true, if: -> { step_type.in?(["script", "command", "prompt"]) }
  validate :workflow_or_run_present
  validate :pr_step_requires_title

  GLOBAL_VARIABLES = ["task_title", "task_body", "task_kind", "repo_owner", "repo_name", "context_files"].freeze

  # Variables visible at a given position in a workflow: globals + each prior
  # step's outputs, plus schema-derived sub-paths for any prior step that has
  # a JSON Schema attached. Each entry is a hash of
  # { "name" => path_or_var, "source" => human_label, "queryable" => bool }.
  # `queryable` is true only for the root output of a schema-bound producer —
  # those vars can be consumed in either inject mode or query mode.
  def self.available_variables_for(workflow, position)
    vars = GLOBAL_VARIABLES.map { |v| { "name" => v, "source" => "global", "queryable" => false } }
    workflow.steps.where(position: ...position.to_i).order(:position).each do |s|
      outputs = s.output_variables
      root = outputs.first
      outputs.each do |v|
        vars << { "name" => v, "source" => s.name, "queryable" => (s.json_schema && v == root).present? }
      end
      next unless s.json_schema && root

      JsonPathResolver.paths_for_schema(s.json_schema.body, prefix: root).each do |path|
        vars << { "name" => path, "source" => s.name, "queryable" => false }
      end
    end
    vars
  end

  # Map of queryable variable name => the producer step's JsonSchema. Used by
  # the executor to build the prompt menu and by the form to know which rows
  # should expose a Query toggle.
  def self.queryable_variable_schemas(workflow, position)
    workflow.steps.where(position: ...position.to_i).order(:position).each_with_object({}) do |s, acc|
      next unless s.json_schema

      root = s.output_variables.first
      acc[root] = s.json_schema if root
    end
  end

  # The variable names this step writes into the run context when it succeeds.
  def output_variables
    case step_type
    when "context_fetch"
      key = config["context_key"]
      key.present? ? [key] : []
    when "pr"
      # `pr` steps emit a fixed set of outputs in addition to anything the
      # author declared via `produces`. Keep the conventional ones first so
      # `produces.first` still resolves to `pr_number` for downstream uses.
      (PR_DEFAULT_OUTPUTS + produces).uniq
    else
      produces
    end
  end

  # Outputs every `pr` step produces, regardless of the user's `produces` list.
  PR_DEFAULT_OUTPUTS = ["pr_number", "pr_url", "branch_name"].freeze

  def produces
    config["produces"] || []
  end

  def consumes
    config["consumes"] || []
  end

  def queries
    config["queries"] || []
  end

  def json_schema_id
    config["json_schema_id"]
  end

  def json_schema
    @json_schema ||= JsonSchema.find_by(id: json_schema_id) if json_schema_id.present?
  end

  def context_project_ids
    Array(config["context_projects"]).map(&:to_i).uniq
  end

  # Returns Project records for context_projects that are currently cloned
  # and on disk. Any selected IDs that don't resolve — deleted project,
  # missing local_path, or never cloned — are logged and silently skipped
  # so the step still runs.
  def ready_context_projects
    ids = context_project_ids
    return [] if ids.empty?

    found = Project.where(id: ids).to_a
    ready = found.select { |p| p.repo_ready? && p.local_path_exists? }

    missing = ids - found.map(&:id)
    not_ready = (found - ready).map(&:id)
    Rails.logger.warn("Step #{id} context project ids not found: #{missing.inspect}") if missing.any?
    Rails.logger.warn("Step #{id} context projects not ready: #{not_ready.inspect}") if not_ready.any?

    ready
  end

  def manual_approval?
    !!manual_approval
  end

  def prompt_body(context = {})
    case step_type
    when "skill"  then TemplateRenderer.new(skill.body, context).render if skill
    when "prompt" then TemplateRenderer.new(body, context).render if body.present?
    end
  end

  private

  def workflow_or_run_present
    return if workflow_id.present? || run_id.present?

    errors.add(:base, "Step must belong to a workflow or a run")
  end

  def pr_step_requires_title
    return unless step_type == "pr"
    return if config.is_a?(Hash) && config["title"].to_s.strip.present?

    errors.add(:base, "PR step requires a title")
  end
end
