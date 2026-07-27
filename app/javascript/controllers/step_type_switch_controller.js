import { Controller } from "@hotwired/stimulus"

const LABELS = {
  skill: "Skill",
  prompt: "Prompt",
  command: "Shell",
  script: "Shell",
  ci_check: "Wait for CI",
  context_fetch: "Fetch context",
  pr: "Open PR",
  self_review: "Self review"
}

// Each type renders its own fields, so changing the type re-fetches the form
// into the inspector frame. A saved step with settings asks first, because
// those settings do not carry over to the new type.
export default class extends Controller {
  static targets = ["select", "warning", "warningText"]
  static values = { url: String, warn: Boolean, current: String }

  changed() {
    const chosen = this.selectTarget.value
    if (chosen === this.currentValue) return this.hideWarning()

    if (this.warnValue) {
      this.pending = chosen
      this.selectTarget.value = this.currentValue
      this.warningTextTarget.textContent =
        `Switching to ${LABELS[chosen] || chosen} clears this step's ${LABELS[this.currentValue] || this.currentValue} settings.`
      this.warningTarget.hidden = false
      return
    }

    this.reload(chosen)
  }

  confirm() {
    const type = this.pending
    this.hideWarning()
    if (type) this.reload(type)
  }

  hideWarning() {
    this.warningTarget.hidden = true
    this.pending = null
  }

  reload(type) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("step_type", type)

    // Carry the name across so a half-filled new step does not lose it.
    const name = this.element.closest("form")?.querySelector("[name='step[name]']")?.value
    if (name) url.searchParams.set("name", name)

    const frame = document.getElementById("step_inspector")
    if (frame) frame.src = url.toString()
    else window.location = url.toString()
  }
}
