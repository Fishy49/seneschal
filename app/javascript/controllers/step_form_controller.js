import { Controller } from "@hotwired/stimulus"

// Within-type behaviour for the step inspector. Which fields exist at all is
// decided on the server by the step's type, so this controller only handles
// the toggles inside one type.
export default class extends Controller {
  static targets = [
    "skillSelect", "skillName", "skillPreview", "previewBody", "previewContent", "previewToggleText",
    "ciMode", "ciPrFields", "ciWorkflowFields", "ciLogFields",
    "fetchMethod", "fetchUrlFields", "fetchProjectFileFields", "fetchPath", "fetchPathDisplay", "fetchSchemaFields",
    "schemaSelect", "schemaOutputFields", "schemaOutputInput", "producesMultiFields", "producesInputWrapper",
    "onFailType", "onFailMaxRounds", "onFailSkillFields", "onFailBodyFields", "onFailReopenFields",
    "saveTemplateCheck", "saveTemplateFields"
  ]
  static values = { skills: Object }

  connect() {
    this.previewVisible = false
    if (this.hasSkillSelectTarget) this.skillChanged()
    if (this.hasCiModeTarget) this.ciModeChanged()
    if (this.hasFetchMethodTarget) this.fetchMethodChanged()
    if (this.hasOnFailTypeTarget) this.onFailChanged()
    this.applySchemaMode({ wipeOnEnter: false })
  }

  schemaChanged() {
    this.applySchemaMode({ wipeOnEnter: true })
  }

  applySchemaMode({ wipeOnEnter }) {
    if (!this.hasSchemaOutputFieldsTarget || !this.hasProducesMultiFieldsTarget) return

    const schemaId = this.hasSchemaSelectTarget ? this.schemaSelectTarget.value : ""
    // The schema picker has three states: inherit (badge shown, schemaId ""),
    // override-with-schema (schemaId set), and override-with-None (schemaId "").
    // schemaId alone can't tell the first from the third - inherit also counts
    // as schema mode (we'll use schema.default_output_variable as produces).
    const inSchemaMode = !!schemaId || this.isInheritMode()

    this.schemaOutputFieldsTarget.style.display = inSchemaMode ? "" : "none"
    this.producesMultiFieldsTarget.style.display = inSchemaMode ? "none" : ""

    if (inSchemaMode) {
      if (wipeOnEnter) this.wipeProducesTags()
      if (this.hasSchemaOutputInputTarget && !this.schemaOutputInputTarget.value) {
        const opt = schemaId ? this.schemaSelectTarget.selectedOptions[0] : null
        if (opt) this.schemaOutputInputTarget.value = this.slugify(opt.textContent)
      }
    }
  }

  isInheritMode() {
    const modeInput = this.element.querySelector('input[name="schema_picker_mode"]')
    return !!modeInput && modeInput.value === "inherit"
  }

  wipeProducesTags() {
    if (!this.hasProducesInputWrapperTarget) return
    const ctrl = this.application.getControllerForElementAndIdentifier(
      this.producesInputWrapperTarget, "produces-input"
    )
    if (ctrl) ctrl.setTags([])
  }

  slugify(name) {
    return String(name || "")
      .trim()
      .toLowerCase()
      .replace(/[^\w]+/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_|_$/g, "")
  }

  fetchMethodChanged() {
    if (!this.hasFetchMethodTarget) return
    const method = this.fetchMethodTarget.value
    if (this.hasFetchUrlFieldsTarget) this.fetchUrlFieldsTarget.style.display = method === "url" ? "" : "none"
    if (this.hasFetchProjectFileFieldsTarget) this.fetchProjectFileFieldsTarget.style.display = method === "project_file" ? "" : "none"
    this.updateFetchSchemaVisibility()
  }

  setProjectFile(path) {
    if (!this.hasFetchPathTarget) return
    this.fetchPathTarget.value = path || ""
    if (this.hasFetchPathDisplayTarget) {
      if (path) {
        this.fetchPathDisplayTarget.textContent = path
      } else {
        this.fetchPathDisplayTarget.innerHTML = '<span class="text-content-muted">No file selected</span>'
      }
    }
    this.updateFetchSchemaVisibility()
  }

  updateFetchSchemaVisibility() {
    if (!this.hasFetchSchemaFieldsTarget) return
    const method = this.hasFetchMethodTarget ? this.fetchMethodTarget.value : ""
    const path = this.hasFetchPathTarget ? this.fetchPathTarget.value.toLowerCase() : ""
    this.fetchSchemaFieldsTarget.style.display = method === "project_file" && path.endsWith(".json") ? "" : "none"
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

    if (this.hasSkillNameTarget) {
      if (hasSkill) {
        const card = document.querySelector(`[data-skill-id="${id}"]`)
        this.skillNameTarget.innerHTML = card ? card.dataset.skillName : `Skill #${id}`
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
      window.hljs?.highlightElement(code)
    } else {
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

  onFailChanged() {
    if (!this.hasOnFailTypeTarget) return
    const type = this.onFailTypeTarget.value
    if (this.hasOnFailMaxRoundsTarget) this.onFailMaxRoundsTarget.style.display = type === "" ? "none" : ""
    if (this.hasOnFailSkillFieldsTarget) this.onFailSkillFieldsTarget.style.display = type === "skill" ? "" : "none"
    if (this.hasOnFailReopenFieldsTarget) this.onFailReopenFieldsTarget.style.display = type === "reopen_previous" ? "" : "none"
    if (this.hasOnFailBodyFieldsTarget) this.onFailBodyFieldsTarget.style.display = ["script", "command"].includes(type) ? "" : "none"
  }

  toggleSaveTemplate() {
    if (!this.hasSaveTemplateFieldsTarget) return
    this.saveTemplateFieldsTarget.style.display = this.saveTemplateCheckTarget.checked ? "" : "none"
  }
}
