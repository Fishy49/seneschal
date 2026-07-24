import { Controller } from "@hotwired/stimulus"

const PROJECT_KEY = "seneschal.launch.project"
const WORKFLOW_KEY = "seneschal.launch.workflow"

function escapeHtml(value) {
  const node = document.createElement("span")
  node.textContent = value
  return node.innerHTML
}

// Cmd/Ctrl+K from anywhere: describe the work, confirm project + workflow,
// launch. Project and workflow default to whatever was used last.
export default class extends Controller {
  static targets = ["overlay", "description", "project", "workflow", "error", "submit"]
  static values = { optionsUrl: String, launchUrl: String }

  connect() {
    this.projects = null
    this.onKeydown = (event) => this.handleKeydown(event)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  get isOpen() {
    return !this.overlayTarget.hidden
  }

  handleKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      if (this.isOpen) this.close()
      else this.open()
      return
    }

    // Only claim Escape while the palette is actually open, so other modals
    // keep their own handler.
    if (event.key === "Escape" && this.isOpen) {
      event.stopPropagation()
      this.close()
    }
  }

  async open() {
    this.overlayTarget.hidden = false
    this.hideError()
    await this.loadOptions()
    this.descriptionTarget.focus()
  }

  close() {
    this.overlayTarget.hidden = true
  }

  backdropClick(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  descriptionKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      this.launch()
    }
  }

  async loadOptions() {
    if (this.projects) return

    try {
      const response = await fetch(this.optionsUrlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("Could not load projects.")
      this.projects = (await response.json()).projects || []
    } catch (error) {
      this.showError(error.message)
      return
    }

    this.projectTarget.innerHTML = this.projects
      .map((project) => `<option value="${project.id}">${escapeHtml(project.name)}</option>`)
      .join("")

    const savedProject = localStorage.getItem(PROJECT_KEY)
    if (savedProject && this.projects.some((project) => String(project.id) === savedProject)) {
      this.projectTarget.value = savedProject
    }
    this.projectChanged()

    const savedWorkflow = localStorage.getItem(WORKFLOW_KEY)
    if (savedWorkflow && Array.from(this.workflowTarget.options).some((o) => o.value === savedWorkflow)) {
      this.workflowTarget.value = savedWorkflow
    }
  }

  projectChanged() {
    const selected = (this.projects || []).find((project) => String(project.id) === this.projectTarget.value)
    const workflows = selected ? selected.workflows : []

    this.workflowTarget.innerHTML = workflows.length
      ? workflows.map((w) => `<option value="${w.id}">${escapeHtml(w.name)}</option>`).join("")
      : '<option value="">No workflows in this project</option>'
  }

  async launch() {
    const description = this.descriptionTarget.value.trim()
    if (!description) {
      this.showError("Describe what you want run.")
      this.descriptionTarget.focus()
      return
    }

    this.hideError()
    this.submitTarget.disabled = true
    this.submitTarget.textContent = "Launching..."

    try {
      const response = await fetch(this.launchUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          description: description,
          project_id: this.projectTarget.value,
          workflow_id: this.workflowTarget.value
        })
      })

      const data = await response.json()
      if (!response.ok) {
        this.showError(data.error || "Could not start the run.")
        return
      }

      localStorage.setItem(PROJECT_KEY, this.projectTarget.value)
      localStorage.setItem(WORKFLOW_KEY, this.workflowTarget.value)
      window.location = data.redirect
    } catch (error) {
      this.showError(error.message)
    } finally {
      this.submitTarget.disabled = false
      this.submitTarget.textContent = "Launch"
    }
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  hideError() {
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }
}
