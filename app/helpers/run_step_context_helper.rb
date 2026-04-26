module RunStepContextHelper # rubocop:disable Metrics/ModuleLength
  CLAUDE_MD_MAX_BYTES = 64 * 1024

  # Returns an ordered list of context sources Claude is expected to see for
  # this run_step, with each source's resolved content (or a blank message).
  # Each entry: { key:, title:, subtitle:, content:, blank: }
  def step_context_sources(run_step)
    step = run_step.step
    project = step.workflow&.project || run_step.run.workflow.project

    sections = []
    sections << claude_md_section(project)
    sections << project_markdown_section(project)
    sections << skill_body_section(step)
    sections << input_context_section(step, run_step)
    sections << consumes_section(step, run_step.run)
    sections << produces_section(step)
    sections << context_projects_section(step)
    sections.compact
  end

  private

  def claude_md_section(project)
    return nil if project&.local_path.blank?

    path = File.join(project.local_path, "CLAUDE.md")
    if File.exist?(path)
      content = begin
        File.read(path, CLAUDE_MD_MAX_BYTES)
      rescue StandardError => e
        "(Could not read #{path}: #{e.message})"
      end
      truncated = File.size(path) > CLAUDE_MD_MAX_BYTES ? " (truncated to #{CLAUDE_MD_MAX_BYTES / 1024}KB)" : ""
      {
        key: "claude_md",
        title: "CLAUDE.md (repo)",
        subtitle: "#{path}#{truncated}",
        content: content,
        blank: false
      }
    else
      {
        key: "claude_md",
        title: "CLAUDE.md (repo)",
        subtitle: path,
        content: nil,
        blank: "No CLAUDE.md found in repo root."
      }
    end
  end

  def project_markdown_section(project)
    {
      key: "project_markdown_context",
      title: "Project Markdown Context",
      subtitle: project&.name,
      content: project&.markdown_context.presence,
      blank: "Project has no markdown_context configured."
    }
  end

  def skill_body_section(step)
    return nil unless step.step_type == "skill" && step.skill

    {
      key: "skill_body",
      title: "Skill Prompt Body",
      subtitle: step.skill.name,
      content: step.skill.body.presence,
      blank: "Skill has no body."
    }
  end

  def input_context_section(step, run_step)
    raw = step.input_context.presence
    resolved = run_step.resolved_input_context.presence

    if raw.present? && resolved.present? && raw != resolved
      {
        key: "input_context",
        title: "Step Additional Context",
        subtitle: "resolved from template",
        content: "TEMPLATE:\n#{raw}\n\n---\n\nRESOLVED:\n#{resolved}",
        blank: false
      }
    elsif resolved.present?
      {
        key: "input_context",
        title: "Step Additional Context",
        subtitle: "input_context",
        content: resolved,
        blank: false
      }
    elsif raw.present?
      {
        key: "input_context",
        title: "Step Additional Context",
        subtitle: "input_context (not yet resolved or step pending)",
        content: raw,
        blank: false
      }
    else
      {
        key: "input_context",
        title: "Step Additional Context",
        subtitle: "input_context",
        content: nil,
        blank: "No additional context configured for this step."
      }
    end
  end

  def consumes_section(step, run)
    return nil if step.consumes.blank?

    blocks = step.consumes.map do |name|
      value = run.context[name] || run.context[name.to_s]
      "<#{name}>\n#{value.presence || "(empty — not yet produced)"}\n</#{name}>"
    end

    {
      key: "consumes",
      title: "Input Variables (consumes)",
      subtitle: step.consumes.join(", "),
      content: blocks.join("\n\n"),
      blank: false
    }
  end

  def produces_section(step)
    return nil if step.produces.blank?

    {
      key: "produces",
      title: "Required Output Variables (produces)",
      subtitle: step.produces.join(", "),
      content: step.produces.map { |v| "#{v}: <value>" }.join("\n"),
      blank: false
    }
  end

  def context_projects_section(step)
    projects = step.ready_context_projects
    return nil if projects.empty?

    {
      key: "context_projects",
      title: "Available Project Directories",
      subtitle: "#{projects.size} project#{"s" if projects.size != 1}",
      content: projects.map { |p| "- #{p.name}: #{p.local_path}" }.join("\n"),
      blank: false
    }
  end
end
