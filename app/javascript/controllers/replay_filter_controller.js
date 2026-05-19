import { Controller } from "@hotwired/stimulus"

// Toggles the visibility of trajectory entries on the Replay view based on
// per-kind chip state. The filter is purely client-side — every entry is
// rendered server-side; we just hide the ones the user toggled off.
//
// Targets:
//   - checkbox: one filter chip <input> per kind, with data-kind="<kind>"
//   - entry:    a trajectory entry <li> with data-kind="<kind>"
//   - timeline: the wrapping container; its presence makes selectors stable
export default class extends Controller {
  static targets = ["checkbox", "entry", "timeline"]

  connect() {
    this.apply()
  }

  toggle() {
    this.apply()
  }

  apply() {
    const allowed = new Set(
      this.checkboxTargets.filter((cb) => cb.checked).map((cb) => cb.dataset.kind)
    )
    this.entryTargets.forEach((entry) => {
      entry.style.display = allowed.has(entry.dataset.kind) ? "" : "none"
    })
  }
}
