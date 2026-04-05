import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "output"]

  connect() {
    const code = document.createElement("code")
    code.className = "language-markdown"
    code.textContent = this.sourceTarget.innerHTML
    const pre = document.createElement("pre")
    pre.appendChild(code)
    this.outputTarget.replaceChildren(pre)
    window.hljs.highlightElement(code)
  }
}
