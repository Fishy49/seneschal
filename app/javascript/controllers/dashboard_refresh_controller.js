import { Controller } from "@hotwired/stimulus"

// Re-fetches the current page and swaps only the marked regions, so a run that
// parks for approval surfaces without a manual refresh. Idles while the tab is
// hidden and leaves the DOM alone when the markup has not changed.
export default class extends Controller {
  static targets = ["region"]
  static values = { interval: { type: Number, default: 5000 } }

  connect() {
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  async refresh() {
    if (document.hidden) return

    let response
    try {
      response = await fetch(window.location.href, { headers: { Accept: "text/html" } })
    } catch {
      return
    }
    if (!response.ok) return

    const fresh = new DOMParser().parseFromString(await response.text(), "text/html")
    this.regionTargets.forEach((region) => {
      const replacement = fresh.getElementById(region.id)
      if (replacement && replacement.innerHTML !== region.innerHTML) {
        region.innerHTML = replacement.innerHTML
      }
    })
  }
}
