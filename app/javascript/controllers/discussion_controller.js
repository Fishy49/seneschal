import { Controller } from "@hotwired/stimulus"

// Glue for a discussion composer. On the run page this sits on the container
// that holds both the steps column and the discussion card, so a step row can
// hand the composer its step ("Comment on this step") from the other column.
// On task pages it wraps a single thread and only the reset matters.
export default class extends Controller {
  static targets = ["select", "body"]

  // The comment itself arrives as a turbo_stream append; all the form has to
  // do afterwards is empty itself.
  submitEnd(event) {
    if (event.detail.success) this.bodyTarget.value = ""
  }

  composeFor(event) {
    const value = event.params.value
    if (this.hasSelectTarget && value) this.selectTarget.value = value
    this.bodyTarget.scrollIntoView({ behavior: "smooth", block: "center" })
    this.bodyTarget.focus({ preventScroll: true })
  }
}
