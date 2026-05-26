import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modeNew", "modeReplace", "newOptions", "replaceOptions"]

  connect() {
    this.modeChanged()
  }

  modeChanged() {
    const replaceChecked = this.hasModeReplaceTarget && this.modeReplaceTarget.checked
    this.newOptionsTarget.classList.toggle("hidden", replaceChecked)
    this.replaceOptionsTarget.classList.toggle("hidden", !replaceChecked)
  }
}
