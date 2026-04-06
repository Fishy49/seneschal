import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "type", "list", "empty"]

  filter() {
    const query = this.searchTarget.value.toLowerCase().trim()
    const type = this.hasTypeTarget ? this.typeTarget.value : ""
    const rows = this.listTarget.querySelectorAll("tr[data-searchable]")
    let anyVisible = false

    rows.forEach(row => {
      const matchesSearch = query === "" || row.dataset.searchable.includes(query)
      const matchesType = type === "" || row.dataset.type === type
      const visible = matchesSearch && matchesType
      row.style.display = visible ? "" : "none"
      if (visible) anyVisible = true
    })

    this.emptyTarget.style.display = anyVisible ? "none" : ""
  }
}
