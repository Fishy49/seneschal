import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "icon"]
  static values = {
    storageKey: { type: String, default: "sidebar_projects_open" },
    defaultOpen: { type: Boolean, default: false }
  }

  connect() {
    const stored = localStorage.getItem(this.storageKeyValue)
    const open = stored === null ? this.defaultOpenValue : stored === "true"
    this.#apply(open)
  }

  toggle() {
    const open = this.listTarget.style.display === "none"
    this.#apply(open)
    localStorage.setItem(this.storageKeyValue, open)
  }

  #apply(open) {
    this.listTarget.style.display = open ? "" : "none"
    if (this.hasIconTarget) {
      this.iconTarget.textContent = open ? "▾" : "▶"
    }
  }
}
