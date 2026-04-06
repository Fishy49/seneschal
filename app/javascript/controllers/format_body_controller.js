import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["btn", "input"]
  static values = { url: String }

  async format() {
    // Read from the editor element directly — dictation may bypass CodeJar's onUpdate
    const editor = this.element.querySelector("[data-code-editor-target='editor']")
    const text = (editor?.textContent || this.inputTarget.value).trim()
    if (!text) return

    const original = this.btnTarget.textContent
    this.btnTarget.textContent = "Formatting..."
    this.btnTarget.disabled = true

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ body: text })
      })

      const data = await response.json()

      if (response.ok && data.formatted) {
        this.inputTarget.value = data.formatted

        // Update CodeJar editor if present
        const editor = this.element.querySelector("[data-code-editor-target='editor']")
        if (editor) {
          const codeEditor = this.application.getControllerForElementAndIdentifier(this.element, "code-editor")
          if (codeEditor?.jar) codeEditor.jar.updateCode(data.formatted)
        }
      } else {
        alert(data.error || "Formatting failed.")
      }
    } catch (e) {
      alert("Formatting failed: " + e.message)
    } finally {
      this.btnTarget.textContent = original
      this.btnTarget.disabled = false
    }
  }
}
