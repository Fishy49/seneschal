import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["btn", "results", "selectedFiles"]
  static values = { url: String }

  async suggest() {
    const editor = this.element.closest("form")?.querySelector("[data-code-editor-target='editor']")
    const bodyInput = this.element.closest("form")?.querySelector("[name='pipeline_task[body]']")
    const text = (editor?.textContent || bodyInput?.value || "").trim()
    if (!text) return

    const original = this.btnTarget.textContent
    this.btnTarget.textContent = "Analyzing..."
    this.btnTarget.disabled = true

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ description: text })
      })

      const data = await response.json()

      if (response.ok && data.files) {
        this.renderSuggestions(data.files)
      } else {
        this.resultsTarget.innerHTML = `<p class="text-sm text-danger">${data.error || "Suggestion failed."}</p>`
      }
    } catch (e) {
      this.resultsTarget.innerHTML = `<p class="text-sm text-danger">Suggestion failed: ${e.message}</p>`
    } finally {
      this.btnTarget.textContent = original
      this.btnTarget.disabled = false
    }
  }

  renderSuggestions(files) {
    if (!files.length) {
      this.resultsTarget.innerHTML = '<p class="text-sm text-content-muted">No relevant files found.</p>'
      return
    }

    const html = files.map(f => `
      <label class="flex items-start gap-2 py-1.5 cursor-pointer hover:bg-surface-input rounded px-2 -mx-2">
        <input type="checkbox" checked
               value="${this.escapeAttr(f.path)}"
               data-reason="${this.escapeAttr(f.reason || "")}"
               data-action="change->task-suggestions#updateSelected"
               class="mt-0.5 rounded border-edge" />
        <div class="flex-1 min-w-0">
          <div class="text-sm font-mono text-content truncate">${this.escapeHtml(f.path)}</div>
          <div class="text-xs text-content-muted">${this.escapeHtml(f.reason || "")}</div>
        </div>
      </label>
    `).join("")

    this.resultsTarget.innerHTML = html
    this.updateSelected()
  }

  updateSelected() {
    const checked = Array.from(this.resultsTarget.querySelectorAll("input[type=checkbox]:checked"))
    const files = checked.map(cb => ({ path: cb.value, reason: cb.dataset.reason || "" }))
    this.selectedFilesTarget.value = JSON.stringify(files)
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str || ""
    return div.innerHTML
  }

  escapeAttr(str) {
    return (str || "").replace(/&/g, "&amp;").replace(/"/g, "&quot;")
  }
}
