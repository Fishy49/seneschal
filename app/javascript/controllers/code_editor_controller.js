import { Controller } from "@hotwired/stimulus"
import { CodeJar } from "codejar"

export default class extends Controller {
  static targets = ["editor", "input"]

  connect() {
    const highlight = (el) => {
      const result = window.hljs.highlight(el.textContent, { language: "markdown" })
      el.innerHTML = result.value
    }

    this.jar = CodeJar(this.editorTarget, highlight, { tab: "  " })
    this.jar.updateCode(this.inputTarget.value)

    this.jar.onUpdate((code) => {
      this.inputTarget.value = code
    })
  }

  disconnect() {
    this.jar.destroy()
  }
}
