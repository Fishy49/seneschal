import { Controller } from "@hotwired/stimulus"

// Opens a modal showing a single previewable asset. Reads the asset metadata
// from data values on the controller element so each tile drives its own
// modal without needing a server round-trip.
export default class extends Controller {
  static values = {
    src: String,
    kind: String,
    label: String,
    contentType: String,
    available: { type: Boolean, default: true }
  }

  open() {
    this.overlay = document.createElement("div")
    this.overlay.className = "fixed inset-0 z-50 flex items-center justify-center bg-black/60 transition-opacity duration-150"
    this.overlay.addEventListener("click", (e) => {
      if (e.target === this.overlay) this.close()
    })

    const modal = document.createElement("div")
    modal.className = "bg-surface-card border border-edge rounded-xl shadow-2xl w-[90vw] max-w-4xl max-h-[90vh] flex flex-col"

    const header = document.createElement("div")
    header.className = "flex items-center justify-between px-5 py-4 border-b border-edge shrink-0"
    const h2 = document.createElement("h2")
    h2.className = "text-lg font-semibold truncate"
    h2.textContent = this.labelValue || "Asset"
    const closeBtn = document.createElement("button")
    closeBtn.type = "button"
    closeBtn.className = "p-1 text-content-muted hover:text-content bg-transparent border-none cursor-pointer text-lg shrink-0"
    closeBtn.innerHTML = "&times;"
    closeBtn.addEventListener("click", () => this.close())
    header.appendChild(h2)
    header.appendChild(closeBtn)

    const body = document.createElement("div")
    body.className = "flex-1 overflow-auto p-5 flex items-center justify-center bg-surface-input"
    body.appendChild(this.buildPlayer())

    modal.appendChild(header)
    modal.appendChild(body)
    this.overlay.appendChild(modal)
    document.body.appendChild(this.overlay)

    this.escHandler = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.escHandler)
  }

  buildPlayer() {
    if (!this.availableValue) {
      const note = document.createElement("p")
      note.className = "text-sm text-content-muted italic"
      note.textContent = "This asset's file is no longer available. The worktree may have been cleaned up since the run finished."
      return note
    }

    switch (this.kindValue) {
      case "image": {
        const img = document.createElement("img")
        img.src = this.srcValue
        img.alt = this.labelValue
        img.className = "max-w-full max-h-[75vh] object-contain"
        return img
      }
      case "audio": {
        const audio = document.createElement("audio")
        audio.src = this.srcValue
        audio.controls = true
        audio.className = "w-full"
        return audio
      }
      case "video": {
        const video = document.createElement("video")
        video.src = this.srcValue
        video.controls = true
        video.className = "max-w-full max-h-[75vh]"
        return video
      }
      default: {
        const link = document.createElement("a")
        link.href = this.srcValue
        link.textContent = `Download ${this.labelValue}`
        link.className = "text-accent underline"
        link.target = "_blank"
        return link
      }
    }
  }

  close() {
    this.overlay?.remove()
    document.removeEventListener("keydown", this.escHandler)
  }
}
