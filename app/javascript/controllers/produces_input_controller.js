import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tagList", "newInput", "hiddenInput", "datalist"]
  static values = { suggestionsUrl: String, initialValue: String }

  connect() {
    const raw = this.initialValueValue || ""
    this.tags = [...new Set(raw.split(",").map(t => t.trim()).filter(Boolean))]
    this.render()
    this.syncHidden()
    if (this.suggestionsUrlValue) {
      fetch(this.suggestionsUrlValue, { headers: { Accept: "application/json" } })
        .then(r => r.json())
        .then(data => {
          this.datalistTarget.innerHTML = (data.suggestions || [])
            .map(s => `<option value="${s}">`)
            .join("")
        })
        .catch(() => {})
    }
  }

  keydown(e) {
    if (e.key === "Enter") {
      e.preventDefault()
      this.add()
    } else if (e.key === "Backspace" && this.newInputTarget.value === "") {
      this.tags.pop()
      this.render()
      this.syncHidden()
    }
  }

  add() {
    const val = this.newInputTarget.value.trim()
    if (!val) return

    if (this.tags.includes(val)) {
      const chip = this.tagListTarget.querySelector(`[data-tag="${CSS.escape(val)}"]`)
      if (chip) {
        chip.classList.add("bg-warning/30")
        setTimeout(() => chip.classList.remove("bg-warning/30"), 600)
      }
      this.newInputTarget.value = ""
      return
    }

    this.tags.push(val)
    this.newInputTarget.value = ""
    this.render()
    this.syncHidden()
  }

  input() {}

  remove(event) {
    const idx = parseInt(event.params.index, 10)
    this.tags.splice(idx, 1)
    this.render()
    this.syncHidden()
  }

  setTags(newTags) {
    this.tags = [...new Set((newTags || []).map(t => String(t).trim()).filter(Boolean))]
    this.render()
    this.syncHidden()
  }

  render() {
    this.tagListTarget.replaceChildren(...this.tags.map((tag, i) => this.buildChip(tag, i)))
  }

  buildChip(tag, index) {
    const li = document.createElement("li")
    li.dataset.tag = tag
    li.className = "inline-flex items-center gap-1 px-2 py-0.5 bg-surface-input border border-edge rounded text-xs font-mono transition-colors"
    li.appendChild(document.createTextNode(tag))

    const btn = document.createElement("button")
    btn.type = "button"
    btn.dataset.action = "produces-input#remove"
    btn.dataset.producesInputIndexParam = index
    btn.className = "text-content-muted hover:text-danger leading-none bg-transparent border-none cursor-pointer p-0 ml-0.5"
    btn.innerHTML = "&times;"
    li.appendChild(btn)

    return li
  }

  syncHidden() {
    this.hiddenInputTarget.value = this.tags.join(",")
  }
}
