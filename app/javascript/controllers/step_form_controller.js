import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "typeSelect", "skillFields", "bodyFields", "bodyLabel", "claudeConfigFields", "ciCheckFields", "contextFetchFields",
    "skillSelect", "skillName", "skillPreview", "previewBody", "previewContent", "previewToggleText",
    "ciMode", "ciPrFields", "ciWorkflowFields", "ciLogFields",
    "saveTemplateCheck", "saveTemplateFields"
  ]
  static values = { skills: Object, templates: Object }

  connect() {
    this.previewVisible = false
    this.toggle()
    if (this.hasSkillSelectTarget) this.skillChanged()
    if (this.hasCiModeTarget) this.ciModeChanged()
  }

  toggle() {
    const type = this.typeSelectTarget.value
    this.skillFieldsTarget.style.display = type === "skill" ? "" : "none"
    this.bodyFieldsTarget.style.display = ["script", "command", "prompt"].includes(type) ? "" : "none"
    if (this.hasClaudeConfigFieldsTarget) {
      this.claudeConfigFieldsTarget.style.display = ["skill", "prompt"].includes(type) ? "" : "none"
    }
    if (this.hasBodyLabelTarget) {
      const labels = { script: "Script", command: "Command", prompt: "Prompt" }
      this.bodyLabelTarget.textContent = labels[type] || "Body"
    }
    if (this.hasCiCheckFieldsTarget) {
      this.ciCheckFieldsTarget.style.display = type === "ci_check" ? "" : "none"
    }
    if (this.hasContextFetchFieldsTarget) {
      this.contextFetchFieldsTarget.style.display = type === "context_fetch" ? "" : "none"
    }
  }

  ciModeChanged() {
    if (!this.hasCiModeTarget) return
    const isWorkflow = this.ciModeTarget.value === "workflow"
    if (this.hasCiPrFieldsTarget) this.ciPrFieldsTarget.style.display = isWorkflow ? "none" : ""
    if (this.hasCiWorkflowFieldsTarget) this.ciWorkflowFieldsTarget.style.display = isWorkflow ? "" : "none"
    if (this.hasCiLogFieldsTarget) this.ciLogFieldsTarget.style.display = isWorkflow ? "none" : ""
  }

  skillChanged() {
    const id = this.skillSelectTarget.value
    const hasSkill = id && this.skillsValue[id]

    this.skillPreviewTarget.style.display = hasSkill ? "" : "none"

    // Update displayed skill name
    if (this.hasSkillNameTarget) {
      if (hasSkill) {
        // Try to find the name from the skill panel card, or fall back to the skills data
        const card = document.querySelector(`[data-skill-id="${id}"]`)
        const name = card ? card.dataset.skillName : `Skill #${id}`
        this.skillNameTarget.innerHTML = name
      } else {
        this.skillNameTarget.innerHTML = '<span class="text-content-muted">No skill selected</span>'
      }
    }

    if (hasSkill) {
      const code = document.createElement("code")
      code.className = "language-markdown"
      code.textContent = this.skillsValue[id]
      const pre = document.createElement("pre")
      pre.appendChild(code)
      this.previewContentTarget.replaceChildren(pre)
      window.hljs.highlightElement(code)
    }

    if (!hasSkill) {
      this.previewVisible = false
      this.previewBodyTarget.style.display = "none"
      this.previewToggleTextTarget.textContent = "Show"
    }
  }

  togglePreview() {
    this.previewVisible = !this.previewVisible
    this.previewBodyTarget.style.display = this.previewVisible ? "" : "none"
    this.previewToggleTextTarget.textContent = this.previewVisible ? "Hide" : "Show"
  }

  toggleSaveTemplate() {
    if (!this.hasSaveTemplateFieldsTarget) return
    this.saveTemplateFieldsTarget.style.display = this.saveTemplateCheckTarget.checked ? "" : "none"
  }

  loadTemplate(templateId) {
    const template = this.templatesValue[templateId]
    if (!template) return

    const cfg = template.config || {}

    // Basic fields
    this.field("step[name]").value = template.name || ""
    this.typeSelectTarget.value = template.step_type
    this.field("step[body]").value = template.body || ""
    this.field("step[max_retries]").value = template.max_retries
    this.field("step[timeout]").value = template.timeout
    this.field("step[input_context]").value = template.input_context || ""
    this.field("step[injectable_only]").checked = template.injectable_only

    // Skill / Prompt config (shared Claude config)
    if (template.step_type === "skill" || template.step_type === "prompt") {
      if (template.step_type === "skill" && this.hasSkillSelectTarget && template.skill_id) {
        this.skillSelectTarget.value = template.skill_id
        if (this.hasSkillNameTarget && template.skill_name) {
          this.skillNameTarget.textContent = template.skill_name
        }
        this.skillChanged()
      }
      this.field("skill_model").value = cfg.model || ""
      this.field("skill_effort").value = cfg.effort || "medium"
      this.field("skill_max_turns").value = cfg.max_turns || ""
      this.field("skill_capture_output").value = cfg.capture_output || ""
      this.field("skill_outputs").value = cfg.outputs ? JSON.stringify(cfg.outputs) : ""
      this.field("skill_allowed_tools").value = cfg.allowed_tools || ""
    }

    // Context Fetch config
    if (template.step_type === "context_fetch") {
      this.field("fetch_method").value = cfg.method || "url"
      this.field("fetch_url").value = cfg.url || ""
      this.field("fetch_context_key").value = cfg.context_key || ""
    }

    // CI Check config
    if (template.step_type === "ci_check") {
      this.field("ci_mode").value = cfg.mode || "pr"
      this.field("ci_poll_interval").value = cfg.poll_interval || 30
      this.field("ci_max_log_chars").value = cfg.max_log_chars || 10000
      this.field("ci_log_from").value = cfg.log_from || "end"
      this.field("ci_pr").value = cfg.pr || "${pr_number}"
      this.field("ci_workflow").value = cfg.workflow || ""
      this.field("ci_ref").value = cfg.ref || "${branch}"
      const trigger = this.element.querySelector('[name="ci_trigger"]')
      if (trigger) trigger.checked = !!cfg.trigger
      if (this.hasCiModeTarget) this.ciModeChanged()
    }

    this.toggle()
  }

  field(name) {
    return this.element.querySelector(`[name="${name}"]`) || { value: "", checked: false }
  }
}
