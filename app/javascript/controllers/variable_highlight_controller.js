import { Controller } from "@hotwired/stimulus"

const ACTIVE = ["ring-2", "ring-accent", "ring-offset-1", "ring-offset-surface-card"]

// Clicking a variable in the strip lights up every pill naming it, so you can
// see which step produces it and which steps read it.
export default class extends Controller {
  static targets = ["pill"]

  toggle(event) {
    const name = event.currentTarget.dataset.variable
    const alreadyOn = event.currentTarget.dataset.variableActive === "true"

    this.clear()
    if (alreadyOn) return

    this.pillTargets
      .filter((pill) => pill.dataset.variable === name)
      .forEach((pill) => {
        pill.classList.add(...ACTIVE)
        pill.dataset.variableActive = "true"
      })
  }

  clear() {
    this.pillTargets.forEach((pill) => {
      pill.classList.remove(...ACTIVE)
      delete pill.dataset.variableActive
    })
  }
}
