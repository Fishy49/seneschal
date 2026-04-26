import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "toggle", "form", "input", "error", "submit"]

  open(event) {
    event.preventDefault()
    this.toggleTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.inputTarget.focus()
  }

  cancel(event) {
    event.preventDefault()
    this.#reset()
  }

  async submit(event) {
    event.preventDefault()
    const name = this.inputTarget.value.trim()
    if (!name) {
      this.#showError("Name can't be blank")
      return
    }

    this.submitTarget.disabled = true
    this.#clearError()

    try {
      const response = await fetch("/project_groups.json", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.#csrfToken()
        },
        body: JSON.stringify({ project_group: { name } })
      })

      const data = await response.json()

      if (response.ok) {
        this.#addOption(data.id, data.name)
        this.#reset()
      } else {
        this.#showError((data.errors || ["Could not create group"]).join(", "))
      }
    } catch (_e) {
      this.#showError("Network error. Please try again.")
    } finally {
      this.submitTarget.disabled = false
    }
  }

  // Submit on Enter inside the inline name input (without submitting the outer form)
  keydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.submit(event)
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.#reset()
    }
  }

  #addOption(id, name) {
    const select = this.selectTarget
    const option = new Option(name, id, true, true)
    // Insert in alphabetical order, but after the blank "(no group)" option
    const options = Array.from(select.options).slice(1)
    const insertBefore = options.find(o => o.text.localeCompare(name) > 0)
    if (insertBefore) {
      select.add(option, insertBefore)
    } else {
      select.add(option)
    }
    select.value = id
    select.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #reset() {
    this.inputTarget.value = ""
    this.#clearError()
    this.formTarget.classList.add("hidden")
    this.toggleTarget.classList.remove("hidden")
  }

  #showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  #clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
