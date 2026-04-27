import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template"]
  static values = { title: String }

  open() {
    this.overlay = document.createElement("div")
    this.overlay.className = "fixed inset-0 z-50 flex items-center justify-center bg-black/60 transition-opacity duration-150"
    this.overlay.addEventListener("click", (e) => {
      if (e.target === this.overlay) this.close()
    })

    const modal = document.createElement("div")
    modal.className = "bg-surface-card border border-edge rounded-xl shadow-2xl w-[90vw] max-w-3xl max-h-[85vh] flex flex-col"

    const header = document.createElement("div")
    header.className = "flex items-center justify-between px-5 py-4 border-b border-edge shrink-0"
    const h2 = document.createElement("h2")
    h2.className = "text-lg font-semibold"
    h2.textContent = this.titleValue || "Context"
    const closeBtn = document.createElement("button")
    closeBtn.type = "button"
    closeBtn.className = "p-1 text-content-muted hover:text-content bg-transparent border-none cursor-pointer text-lg"
    closeBtn.innerHTML = "&times;"
    closeBtn.addEventListener("click", () => this.close())
    header.appendChild(h2)
    header.appendChild(closeBtn)

    const body = document.createElement("div")
    body.className = "flex-1 overflow-y-auto p-5"
    body.appendChild(this.templateTarget.content.cloneNode(true))

    modal.appendChild(header)
    modal.appendChild(body)
    this.overlay.appendChild(modal)
    document.body.appendChild(this.overlay)

    this.escHandler = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.escHandler)
  }

  close() {
    this.overlay?.remove()
    document.removeEventListener("keydown", this.escHandler)
  }
}
