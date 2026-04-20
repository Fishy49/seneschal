import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "input", "messages", "pagePath"]
  static values = { createUrl: String }

  connect() {
    this.updatePagePath()
    window.addEventListener("keydown", this.handleKeydown)
    this.element.addEventListener("submit", this.handleSubmit, true)
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
    this.element.removeEventListener("submit", this.handleSubmit, true)
  }

  handleSubmit = (event) => {
    const path = window.location.pathname
    event.target.querySelectorAll('input[name="current_page_path"]').forEach((input) => {
      input.value = path
    })
  }

  toggle() {
    if (this.panelTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    if (this.panelTarget.innerHTML.trim() === "") {
      this.loadPanel()
    }
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.classList.add("flex", "flex-col")
    this.scrollToBottom()
    setTimeout(() => {
      if (this.hasInputTarget) this.inputTarget.focus()
    }, 100)
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.panelTarget.classList.remove("flex", "flex-col")
  }

  async loadPanel() {
    const response = await fetch(this.createUrlValue, {
      method: "POST",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
      }
    })
    if (response.ok) {
      const html = await response.text()
      // Turbo handles turbo-stream responses
      const reader = new DOMParser().parseFromString(html, "text/html")
      const content = reader.querySelector("template")?.innerHTML
      if (content) this.panelTarget.innerHTML = content
    }
  }

  submitMessage(event) {
    event.preventDefault()
    this.updatePagePath()
    const form = event.target
    form.requestSubmit()
    if (this.hasInputTarget) this.inputTarget.value = ""
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.updatePagePath()
      event.target.closest("form")?.requestSubmit()
      if (this.hasInputTarget) this.inputTarget.value = ""
    }
  }

  scrollToBottom() {
    if (this.hasMessagesTarget) {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }
  }

  updatePagePath() {
    if (this.hasPagePathTarget) {
      this.pagePathTarget.value = window.location.pathname
    }
  }

  handleKeydown = (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key === "/") {
      event.preventDefault()
      this.toggle()
    }
    if (event.key === "Escape" && !this.panelTarget.classList.contains("hidden")) {
      this.close()
    }
  }

  messagesTargetConnected() {
    this.scrollToBottom()
  }

  pagePathTargetConnected() {
    this.updatePagePath()
  }
}
