import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = { url: String }

  connect() {
    this.dragItem = null
  }

  dragstart(event) {
    this.dragItem = event.currentTarget
    event.currentTarget.classList.add("opacity-40")
    event.dataTransfer.effectAllowed = "move"
  }

  dragend(event) {
    event.currentTarget.classList.remove("opacity-40")
    this.element.querySelectorAll("[data-drag-over]").forEach(el => {
      delete el.dataset.dragOver
      el.classList.remove("border-t-2", "border-t-accent")
    })
    this.dragItem = null
  }

  dragover(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const target = event.currentTarget
    if (target === this.dragItem) return

    // Clear previous indicators
    this.itemTargets.forEach(el => {
      delete el.dataset.dragOver
      el.classList.remove("border-t-2", "border-t-accent")
    })

    target.dataset.dragOver = "true"
    target.classList.add("border-t-2", "border-t-accent")
  }

  dragleave(event) {
    const target = event.currentTarget
    delete target.dataset.dragOver
    target.classList.remove("border-t-2", "border-t-accent")
  }

  drop(event) {
    event.preventDefault()
    const target = event.currentTarget
    if (!this.dragItem || target === this.dragItem) return

    target.classList.remove("border-t-2", "border-t-accent")
    delete target.dataset.dragOver

    // Move the DOM element
    const list = this.dragItem.parentNode
    list.insertBefore(this.dragItem, target)

    this.persist()
  }

  persist() {
    const ids = this.itemTargets.map(el => el.dataset.stepId)

    // Update visible position badges
    this.itemTargets.forEach((el, index) => {
      const badge = el.querySelector("[data-position-badge]")
      if (badge) badge.textContent = index + 1
    })

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token,
        "Accept": "application/json"
      },
      body: JSON.stringify({ step_ids: ids })
    })
  }
}
