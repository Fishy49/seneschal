import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { base: String }

  populate() {
    const name = this.#projectName()
    if (!name) return

    this.inputTarget.value = `${this.baseValue}/${name}`
  }

  #projectName() {
    // Derive from the name field, or fall back to repo URL
    const nameField = this.element.closest("form").querySelector("[name*='[name]']")
    if (nameField?.value) return nameField.value.trim().toLowerCase().replace(/\s+/g, "_")

    const repoField = this.element.closest("form").querySelector("[name*='[repo_url]']")
    if (repoField?.value) {
      const match = repoField.value.match(/\/([^/]+?)(?:\.git)?$/)
      if (match) return match[1]
    }

    return null
  }
}
