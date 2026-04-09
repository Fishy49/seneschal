import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "panel", "search", "list", "empty"]

  open() {
    this.backdropTarget.style.display = ""
    requestAnimationFrame(() => {
      this.backdropTarget.style.opacity = "1"
      this.panelTarget.style.transform = "translateX(0)"
    })
    this.searchTarget.value = ""
    this.filter()
    setTimeout(() => this.searchTarget.focus(), 200)
    document.addEventListener("keydown", this.handleEsc)
  }

  close() {
    this.backdropTarget.style.opacity = "0"
    this.panelTarget.style.transform = "translateX(100%)"
    setTimeout(() => { this.backdropTarget.style.display = "none" }, 200)
    document.removeEventListener("keydown", this.handleEsc)
  }

  handleEsc = (e) => {
    if (e.key === "Escape") this.close()
  }

  filter() {
    const query = this.searchTarget.value.toLowerCase().trim()
    const cards = this.listTarget.querySelectorAll("[data-skill-id]")
    let anyVisible = false

    cards.forEach(card => {
      const match = query === "" || card.dataset.searchable.includes(query)
      card.style.display = match ? "" : "none"
      if (match) anyVisible = true
    })

    this.emptyTarget.style.display = anyVisible ? "none" : ""
  }

  select(event) {
    const skillId = event.currentTarget.dataset.skillId

    // Set the hidden skill_id field and trigger step-form update
    const form = document.querySelector("[data-controller~='step-form']")
    if (form) {
      const ctrl = this.application.getControllerForElementAndIdentifier(form, "step-form")
      if (ctrl) {
        ctrl.skillSelectTarget.value = skillId
        ctrl.skillChanged()
      }
    }

    this.close()
  }
}
