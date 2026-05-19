class Skill < ApplicationRecord
  SOURCE_KINDS = SkillLoader::SOURCE_KINDS

  belongs_to :project, optional: true
  belongs_to :skill_repo, optional: true
  belongs_to :default_json_schema, class_name: "JsonSchema", optional: true
  has_many :steps, dependent: :nullify
  has_many :step_templates, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: [:project_id, :skill_repo_id] }
  validates :source_kind, presence: true, inclusion: { in: SOURCE_KINDS }
  validates :relative_path, presence: true
  validates :default_output_variable,
            format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must be snake_case (letters, digits, underscores; start with a letter)" },
            allow_blank: true
  validate :default_output_variable_present_when_schema_set

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  scope :shared, -> { where(project_id: nil) }
  scope :for_project, ->(project) { where(project_id: nil).or(where(project_id: project.id)) }

  def shared?
    project_id.nil?
  end

  def project_scoped?
    project_id.present?
  end

  def display_name
    if skill_repo
      "#{skill_repo.name}/#{name}"
    elsif shared?
      name
    else
      "#{project.name}/#{name}"
    end
  end

  def archived?
    archived_at.present?
  end

  def scope_value
    project_scoped? ? "project:#{project_id}" : ""
  end

  # --- Filesystem-backed (agentskills.io SKILL.md) ---

  # Every Skill is filesystem-backed now; this predicate stays as a stable
  # public API for callers that branch on the legacy DB-backed path. Defined
  # by the same fields the create-path validators require.
  def filesystem_backed?
    relative_path.present? && source_kind.present?
  end

  # Absolute path to the skill directory on disk. Returns nil when the
  # owning project / SkillRepo isn't available (unclonded repo, missing
  # skill repo, etc). For "global" skills the path is resolved across
  # SkillLoader.global_roots in priority order.
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
    list_files_under(references_dir).map do |entry|
      next entry unless entry[:name].end_with?(".json")

      entry.merge(looks_like_schema: JsonSchemaSniffer.looks_like_schema?(File.read(entry[:absolute])))
    end
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
  # check and the parse happen at most once per instance. Returns nil when
  # the SKILL.md is missing from disk. Call `refresh_cached_metadata!`
  # (or re-instantiate the record) to invalidate.
  def parsed_skill_md
    return @parsed_skill_md if defined?(@parsed_skill_md)

    path = skill_md_path
    @parsed_skill_md = path && File.exist?(path) ? SkillMdParser.parse(File.read(path)) : nil
  end

  def frontmatter
    return cached_metadata if cached_metadata.present? && !defined?(@parsed_skill_md)

    parsed_skill_md&.frontmatter || {}
  end

  # Returns the body content used as the prompt template — the post-
  # frontmatter portion of SKILL.md on disk. Returns nil when the file is
  # missing; callers that render the prompt (Step#prompt_body) raise a
  # clear error in that case rather than silently propagating nil.
  def body
    parsed_skill_md&.body
  end

  # Sha256 of the SKILL.md contents. nil when the file is missing on disk.
  def compute_content_hash
    path = skill_md_path
    return nil unless path && File.exist?(path)

    Digest::SHA256.file(path).hexdigest
  end

  def refresh_cached_metadata! # rubocop:disable Naming/PredicateMethod
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

  # A schema without an output-variable name is unusable from a Step (we'd
  # have nothing to splice the structured_output into). Fail loudly at
  # save time rather than silently producing broken Step defaults later.
  def default_output_variable_present_when_schema_set
    return if default_json_schema_id.blank? || default_output_variable.present?

    errors.add(:default_output_variable, "is required when a default schema is set")
  end
end
