import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source"]

  copy() {
    navigator.clipboard.writeText(this.sourceTarget.value)
    const btn = this.element.querySelector("button")
    if (btn) {
      const original = btn.textContent
      btn.textContent = "Copied!"
      setTimeout(() => { btn.textContent = original }, 1500)
    }
  }
}
