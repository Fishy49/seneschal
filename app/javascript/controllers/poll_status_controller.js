import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  async poll() {
    const response = await fetch(this.urlValue)
    if (!response.ok) return
    const html = await response.text()
    this.element.outerHTML = html
  }
}
