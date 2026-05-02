import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rejectForm"]

  toggleReject() {
    if (!this.hasRejectFormTarget) return
    const visible = this.rejectFormTarget.style.display !== "none"
    this.rejectFormTarget.style.display = visible ? "none" : ""
  }
}
