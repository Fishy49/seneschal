import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "typeSelect", "skillFields", "bodyFields", "ciCheckFields",
    "skillSelect", "skillPreview", "previewBody", "previewContent", "previewToggleText",
    "ciMode", "ciPrFields", "ciWorkflowFields"
  ]
  static values = { skills: Object }

  connect() {
    this.previewVisible = false
    this.toggle()
    if (this.hasSkillSelectTarget) this.skillChanged()
    if (this.hasCiModeTarget) this.ciModeChanged()
  }

  toggle() {
    const type = this.typeSelectTarget.value
    this.skillFieldsTarget.style.display = type === "skill" ? "" : "none"
    this.bodyFieldsTarget.style.display = (type === "script" || type === "command") ? "" : "none"
    if (this.hasCiCheckFieldsTarget) {
      this.ciCheckFieldsTarget.style.display = type === "ci_check" ? "" : "none"
    }
  }

  ciModeChanged() {
    if (!this.hasCiModeTarget) return
    const isWorkflow = this.ciModeTarget.value === "workflow"
    if (this.hasCiPrFieldsTarget) this.ciPrFieldsTarget.style.display = isWorkflow ? "none" : ""
    if (this.hasCiWorkflowFieldsTarget) this.ciWorkflowFieldsTarget.style.display = isWorkflow ? "" : "none"
  }

  skillChanged() {
    const id = this.skillSelectTarget.value
    const hasSkill = id && this.skillsValue[id]

    this.skillPreviewTarget.style.display = hasSkill ? "" : "none"

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
}
