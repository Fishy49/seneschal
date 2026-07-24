import { Controller } from "@hotwired/stimulus"

// Toggles the visibility of trajectory entries on the Replay view based on
// per-kind chip state. The filter is purely client-side - every entry is
// rendered server-side; we just hide the ones the user toggled off.
//
// Chip state round-trips through the `show` query param so a copied link
// carries the same view. The default set (whatever the ERB renders checked)
// produces no param at all.
//
// Targets:
//   - checkbox: one filter chip <input> per kind, with data-kind="<kind>"
//   - entry:    a trajectory entry <li> with data-kind="<kind>"
//   - timeline: the wrapping container; its presence makes selectors stable
export default class extends Controller {
  static targets = ["checkbox", "entry", "timeline"]

  connect() {
    this.defaults = new Set(this.checkedKinds())
    this.restore()
    this.apply()
  }

  toggle() {
    this.persist()
    this.apply()
  }

  apply() {
    const allowed = new Set(this.checkedKinds())
    this.entryTargets.forEach((entry) => {
      entry.style.display = allowed.has(entry.dataset.kind) ? "" : "none"
    })
  }

  checkedKinds() {
    return this.checkboxTargets.filter((cb) => cb.checked).map((cb) => cb.dataset.kind)
  }

  restore() {
    const param = new URLSearchParams(window.location.search).get("show")
    if (param === null) return

    const wanted = new Set(param.split(",").filter(Boolean))
    this.checkboxTargets.forEach((cb) => { cb.checked = wanted.has(cb.dataset.kind) })
  }

  persist() {
    const on = this.checkedKinds()
    const params = new URLSearchParams(window.location.search)

    if (this.isDefault(on)) params.delete("show")
    else params.set("show", on.join(","))

    const query = params.toString()
    const url = `${window.location.pathname}${query ? `?${query}` : ""}${window.location.hash}`
    history.replaceState({}, "", url)
  }

  isDefault(kinds) {
    return kinds.length === this.defaults.size && kinds.every((kind) => this.defaults.has(kind))
  }
}
