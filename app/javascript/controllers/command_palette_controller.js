import { Controller } from "@hotwired/stimulus"

const PROJECT_KEY = "seneschal.launch.project"
const WORKFLOW_KEY = "seneschal.launch.workflow"

function escapeHtml(value) {
  const node = document.createElement("span")
  node.textContent = value
  return node.innerHTML
}

// Cmd/Ctrl+K from anywhere: one box that searches, jumps, or launches. The
// text doubles as a jump-to query (arrow keys pick a result, Enter goes) and
// as the description for a new run (Cmd/Ctrl+Enter launches). Project and
// workflow default to whatever was used last.
export default class extends Controller {
  static targets = ["overlay", "description", "project", "workflow", "error", "submit", "summary", "composer", "results"]
  static values = { optionsUrl: String, launchUrl: String, searchUrl: String }

  connect() {
    this.projects = null
    this.results = []
    this.selectedIndex = -1
    this.searchTimer = null
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

  // Launch buttons that already know which project they mean, so the palette
  // opens with the workflow list already filtered.
  async openWithProject(event) {
    const projectId = String(event.params?.project ?? "")
    await this.open()
    if (!projectId) return

    const known = Array.from(this.projectTarget.options).some((option) => option.value === projectId)
    if (!known) return

    this.projectTarget.value = projectId
    this.projectChanged()
  }

  close() {
    this.overlayTarget.hidden = true
    this.clearResults()
  }

  backdropClick(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  descriptionKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      this.launch()
      return
    }

    if (!this.results.length) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.moveSelection(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.moveSelection(-1)
    } else if (event.key === "Enter" && this.selectedIndex >= 0) {
      event.preventDefault()
      this.visit(this.results[this.selectedIndex].url)
    }
  }

  // Typing searches; below two characters the list folds away. Plain Enter
  // keeps inserting newlines until a result is actually highlighted.
  queryChanged() {
    clearTimeout(this.searchTimer)
    const query = this.descriptionTarget.value.trim()
    if (!this.hasSearchUrlValue || query.length < 2) {
      this.clearResults()
      return
    }

    this.searchTimer = setTimeout(async () => {
      try {
        const url = new URL(this.searchUrlValue, window.location.origin)
        url.searchParams.set("q", query)
        const response = await fetch(url, { headers: { Accept: "application/json" } })
        if (!response.ok) return
        this.renderResults((await response.json()).results || [])
      } catch {
        // Search is a convenience; a failed fetch just means no list.
      }
    }, 180)
  }

  renderResults(results) {
    this.results = results
    this.selectedIndex = -1
    if (!results.length) {
      this.resultsTarget.hidden = true
      this.resultsTarget.innerHTML = ""
      return
    }

    this.resultsTarget.innerHTML = results
      .map((result, index) => `
        <li><button type="button" data-index="${index}"
              class="w-full flex items-center gap-2.5 px-3 py-2 bg-transparent border-none cursor-pointer text-left text-sm text-content hover:bg-surface-input transition-colors"
              data-action="command-palette#resultClicked">
          <span class="text-[0.6875rem] font-semibold uppercase tracking-wide text-content-faint w-16 shrink-0">${escapeHtml(result.type)}</span>
          <span class="truncate">${escapeHtml(result.label)}</span>
          <span class="ml-auto shrink-0 text-xs text-content-muted">${escapeHtml(result.sublabel || "")}</span>
        </button></li>`)
      .join("")
    this.resultsTarget.hidden = false
  }

  moveSelection(step) {
    const count = this.results.length
    if (!count) return

    if (this.selectedIndex === -1) {
      this.selectedIndex = step > 0 ? 0 : count - 1
    } else {
      this.selectedIndex = (this.selectedIndex + step + count) % count
    }

    this.resultsTarget.querySelectorAll("button").forEach((button, index) => {
      button.classList.toggle("bg-surface-input", index === this.selectedIndex)
      button.setAttribute("aria-selected", String(index === this.selectedIndex))
    })
  }

  resultClicked(event) {
    const index = Number(event.currentTarget.dataset.index)
    if (this.results[index]) this.visit(this.results[index].url)
  }

  visit(url) {
    this.close()
    if (window.Turbo) window.Turbo.visit(url)
    else window.location = url
  }

  clearResults() {
    this.results = []
    this.selectedIndex = -1
    if (this.hasResultsTarget) {
      this.resultsTarget.hidden = true
      this.resultsTarget.innerHTML = ""
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

    this.workflowChanged()
  }

  // The same glance the composer's cards give: how often this workflow has
  // worked, what it costs, and what it can touch.
  workflowChanged() {
    if (!this.hasSummaryTarget) return

    const workflow = this.selectedWorkflow()
    const parts = workflow ? [workflow.stats, workflow.access].filter(Boolean) : []

    this.summaryTarget.textContent = parts.join(" · ")
    this.summaryTarget.hidden = parts.length === 0
    this.updateComposerLink()
  }

  selectedWorkflow() {
    const project = (this.projects || []).find((p) => String(p.id) === this.projectTarget.value)
    if (!project) return null

    return project.workflows.find((w) => String(w.id) === this.workflowTarget.value)
  }

  // Carries what has been typed over to the full composer rather than making
  // someone retype it.
  updateComposerLink() {
    if (!this.hasComposerTarget) return

    const url = new URL(this.composerTarget.dataset.baseHref || this.composerTarget.href, window.location.origin)
    this.composerTarget.dataset.baseHref ||= url.pathname

    url.search = ""
    const description = this.descriptionTarget.value.trim()
    if (description) url.searchParams.set("description", description)
    if (this.projectTarget.value) url.searchParams.set("project_id", this.projectTarget.value)

    this.composerTarget.href = url.toString()
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

    // Forgery protection is off in some environments, and then Rails emits no
    // csrf-token meta tag at all. Send the header only when there is one.
    const headers = { "Content-Type": "application/json", Accept: "application/json" }
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    // Once the redirect is assigned the document starts tearing down; touching
    // the button after that races the navigation.
    let navigating = false

    try {
      const response = await fetch(this.launchUrlValue, {
        method: "POST",
        headers: headers,
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
      navigating = true
      window.location = data.redirect
    } catch (error) {
      this.showError(error.message)
    } finally {
      if (!navigating) {
        this.submitTarget.disabled = false
        this.submitTarget.textContent = "Launch"
      }
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
