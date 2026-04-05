import { Controller } from "@hotwired/stimulus"

// Scrolls the element to the bottom on connect and whenever its content changes.
// Attach with: data-controller="autoscroll"
export default class extends Controller {
  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
