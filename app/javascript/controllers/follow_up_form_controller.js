import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["skillList", "template"]

  addSkill() {
    const clone = this.templateTarget.content.firstElementChild.cloneNode(true)
    this.skillListTarget.appendChild(clone)
  }

  removeSkill(event) {
    event.currentTarget.closest("div").remove()
  }
}
