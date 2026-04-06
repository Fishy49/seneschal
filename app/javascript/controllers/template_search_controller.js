import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "list"]

  connect() {
    this.items = this.listTarget.querySelectorAll("button[data-template-id]")
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()

    if (query === "") {
      this.listTarget.style.display = "none"
      return
    }

    let anyVisible = false
    this.items.forEach(item => {
      const match = item.dataset.searchable.includes(query)
      item.style.display = match ? "" : "none"
      if (match) anyVisible = true
    })

    this.listTarget.style.display = anyVisible ? "" : "none"
  }

  select(event) {
    const templateId = event.currentTarget.dataset.templateId
    const name = event.currentTarget.querySelector(".font-medium").textContent

    // Find the step-form controller on the wrapping element
    const wrapper = this.element.closest(".step-form-wrapper")
    const form = wrapper?.querySelector("[data-controller~='step-form']")
    if (form) {
      const controller = this.application.getControllerForElementAndIdentifier(form, "step-form")
      if (controller) controller.loadTemplate(templateId)
    }

    this.inputTarget.value = name
    this.listTarget.style.display = "none"
  }
}
