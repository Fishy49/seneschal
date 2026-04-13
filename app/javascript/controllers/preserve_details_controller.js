import { Controller } from "@hotwired/stimulus"

// Preserves <details> open/closed state across Turbo Stream replacements.
// Attach to any container with Turbo Stream targets inside it.
export default class extends Controller {
  connect() {
    this.boundHandler = this.handleBeforeRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundHandler)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.boundHandler)
  }

  handleBeforeRender(event) {
    const streamEl = event.target
    if (streamEl.getAttribute("action") !== "replace") return

    const targetId = streamEl.getAttribute("target")
    const targetEl = document.getElementById(targetId)
    if (!targetEl || !this.element.contains(targetEl)) return

    const openKeys = []
    targetEl.querySelectorAll("details[open]").forEach(d => {
      const key = this.keyFor(d)
      if (key) openKeys.push(key)
    })

    if (openKeys.length === 0) return

    const originalRender = event.detail.render
    event.detail.render = (streamElement) => {
      originalRender(streamElement)

      // Restore after the replacement is in the DOM
      const newEl = document.getElementById(targetId)
      if (!newEl) return

      newEl.querySelectorAll("details").forEach(d => {
        const key = this.keyFor(d)
        if (key && openKeys.includes(key)) {
          d.setAttribute("open", "")
        }
      })
    }
  }

  // Build a stable key from the details element's position and summary text
  keyFor(details) {
    const summary = details.querySelector(":scope > summary")
    if (!summary) return null

    // Use the closest identifiable parent + summary text for uniqueness
    const parent = details.closest("[id]")
    const parentId = parent ? parent.id : ""
    const text = summary.textContent.trim().substring(0, 60)
    return `${parentId}::${text}`
  }
}
