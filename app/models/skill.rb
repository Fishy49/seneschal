class Skill < ApplicationRecord
  SOURCE_KINDS = SkillLoader::SOURCE_KINDS

  belongs_to :project, optional: true
  belongs_to :project_group, optional: true
  belongs_to :skill_repo, optional: true
  belongs_to :default_json_schema, class_name: "JsonSchema", optional: true
  has_many :steps, dependent: :nullify
  has_many :step_templates, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: [:project_id, :project_group_id, :skill_repo_id] }
  validates :body, presence: true, unless: :filesystem_backed?
  validates :source_kind, inclusion: { in: SOURCE_KINDS }, allow_nil: true
  validates :default_output_variable,
            format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must be snake_case (letters, digits, underscores; start with a letter)" },
            allow_blank: true
  validate :default_output_variable_present_when_schema_set
  validate :scope_is_exclusive

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  scope :shared, -> { where(project_id: nil, project_group_id: nil) }
  scope :group_scoped, -> { where.not(project_group_id: nil) }
  scope :for_group, ->(group) { where(project_group_id: group.id) }
  scope :for_project, lambda { |project|
    base = where(project_id: nil, project_group_id: nil).or(where(project_id: project.id))
    if project.project_group_id.present?
      base.or(where(project_group_id: project.project_group_id))
    else
      base
    end
  }

  def shared?
    project_id.nil? && project_group_id.nil?
  end

  def group_scoped?
    project_group_id.present?
  end

  def project_scoped?
    project_id.present?
  end

  def display_name
    if skill_repo
      "#{skill_repo.name}/#{name}"
    elsif shared?
      name
    elsif group_scoped?
      "#{project_group.name}/#{name}"
    else
      "#{project.name}/#{name}"
    end
  end

  def archived?
    archived_at.present?
  end

  def scope_value
    if group_scoped?
      "group:#{project_group_id}"
    elsif project_scoped?
      "project:#{project_id}"
    else
      ""
    end
  end

  # --- Filesystem-backed (agentskills.io SKILL.md) ---

  def filesystem_backed?
    relative_path.present? && source_kind.present?
  end

  # Absolute path to the skill directory on disk. Returns nil if this skill is
  # legacy DB-backed, if project_group-scoped (no disk projection yet), or if
  # the owning project / SkillRepo isn't available. For "global" skills the
  # path is resolved across SkillLoader.global_roots in priority order.
  def absolute_path
    return nil unless filesystem_backed?

    case source_kind
    when "global"
      SkillLoader.global_roots.each do |root|
        candidate = File.join(root, relative_path)
        return candidate if File.directory?(candidate)
      end
      File.join(SkillLoader.global_roots.first, relative_path)
    when "skill_repo"
      return nil if skill_repo&.local_path.blank?

      File.join(skill_repo.local_path, relative_path)
    when "project"
      return nil if project&.local_path.blank?

      File.join(project.local_path, ".claude", "skills", relative_path)
    when "project_seneschal"
      return nil if project&.local_path.blank?

      File.join(project.local_path, ".seneschal", "skills", relative_path)
    end
  end

  def skill_md_path
    abs = absolute_path
    abs && File.join(abs, "SKILL.md")
  end

  def scripts_dir
    abs = absolute_path
    abs && File.join(abs, "scripts")
  end

  def references_dir
    abs = absolute_path
    abs && File.join(abs, "references")
  end

  # Sorted relative-path strings for every file under scripts/ or references/.
  # Returns [] when the directory is missing. Used by the show page to surface
  # the auxiliary files that ship alongside SKILL.md as part of an
  # agentskills.io-conformant skill.
  def scripts_files
    list_files_under(scripts_dir)
  end

  def references_files
    list_files_under(references_dir)
  end

  def read_auxiliary_file(kind, relative_filename)
    base = case kind.to_s
           when "scripts" then scripts_dir
           when "references" then references_dir
           end
    return nil if base.nil?

    full = File.expand_path(relative_filename, base)
    # Path-traversal guard: refuse anything that resolves outside the
    # scripts/ or references/ subtree.
    return nil unless full.start_with?(File.expand_path(base) + File::SEPARATOR)
    return nil unless File.file?(full)

    File.read(full)
  end

  # Parsed SKILL.md (frontmatter + body). Memoized — both the `File.exist?`
  # check and the parse happen at most once per instance. Returns nil if the
  # skill isn't filesystem-backed or its SKILL.md is missing from disk; in
  # that case `body` falls back to the legacy DB column. Call
  # `refresh_cached_metadata!` (or re-instantiate the record) to invalidate.
  def parsed_skill_md
    return @parsed_skill_md if defined?(@parsed_skill_md)

    path = skill_md_path
    @parsed_skill_md = path && File.exist?(path) ? SkillMdParser.parse(File.read(path)) : nil
  end

  def frontmatter
    return cached_metadata if cached_metadata.present? && !defined?(@parsed_skill_md)
    return {} unless filesystem_backed?

    parsed_skill_md&.frontmatter || {}
  end

  # Returns the body content used as the prompt template. For filesystem-backed
  # skills it's the post-frontmatter portion of SKILL.md; for legacy DB skills
  # it's the body column. Callers (Step#prompt_body, TemplateRenderer) don't
  # need to care which backing is in use.
  def body
    return super unless filesystem_backed?

    parsed = parsed_skill_md
    parsed ? parsed.body : super
  end

  # Sha256 of the SKILL.md contents. nil for legacy DB skills or when the
  # file is missing on disk.
  def compute_content_hash
    return nil unless filesystem_backed?

    path = skill_md_path
    return nil unless path && File.exist?(path)

    Digest::SHA256.file(path).hexdigest
  end

  def refresh_cached_metadata! # rubocop:disable Naming/PredicateMethod
    return false unless filesystem_backed?

    remove_instance_variable(:@parsed_skill_md) if defined?(@parsed_skill_md)
    fresh = parsed_skill_md
    return false unless fresh

    # Mirror description from frontmatter into the dedicated column so list
    # pages and search predicates don't have to disk-read on every render.
    # cached_metadata stays the source of truth for everything else (allowed-
    # tools, model, version, license, etc.).
    update!(
      cached_metadata: fresh.frontmatter,
      content_hash: compute_content_hash,
      description: fresh.frontmatter["description"].to_s.presence
    )
    true
  end

  private

  def list_files_under(dir)
    return [] if dir.nil? || !File.directory?(dir)

    entries = Dir.glob(File.join(dir, "**", "*")).filter_map do |path|
      next unless File.file?(path)

      relative = Pathname.new(path).relative_path_from(Pathname.new(dir)).to_s
      { name: relative, absolute: path, size: File.size(path) }
    end
    entries.sort_by { |f| f[:name] }
  end

  def scope_is_exclusive
    return unless project_id.present? && project_group_id.present?

    errors.add(:base, "Skill cannot belong to both a project and a project group")
  end

  # A schema without an output-variable name is unusable from a Step (we'd
  # have nothing to splice the structured_output into). Fail loudly at
  # save time rather than silently producing broken Step defaults later.
  def default_output_variable_present_when_schema_set
    return if default_json_schema_id.blank? || default_output_variable.present?

    errors.add(:default_output_variable, "is required when a default schema is set")
  end
end
