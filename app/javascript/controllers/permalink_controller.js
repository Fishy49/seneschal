import { Controller } from "@hotwired/stimulus"

// Copies a link to one element on the current page. Keeps the query string
// (the replay filter chips live there) and replaces any existing hash, so the
// recipient lands on the same element with the same filters applied.
export default class extends Controller {
  static values = { anchor: String }

  async copy() {
    const { origin, pathname, search } = window.location
    const url = `${origin}${pathname}${search}#${this.anchorValue}`

    try {
      await navigator.clipboard.writeText(url)
    } catch {
      return
    }

    const original = this.element.textContent
    this.element.textContent = "Copied"
    setTimeout(() => { this.element.textContent = original }, 1500)
  }
}
