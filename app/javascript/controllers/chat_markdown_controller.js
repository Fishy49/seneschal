import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (!window.marked || !window.DOMPurify) return
    const source = this.element.textContent
    const html = window.DOMPurify.sanitize(
      window.marked.parse(source, { breaks: true, gfm: true })
    )
    this.element.innerHTML = html
    this.element.classList.add("chat-markdown")
  }
}
