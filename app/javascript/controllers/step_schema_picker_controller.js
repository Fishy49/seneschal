import { Controller } from "@hotwired/stimulus"

// Toggles the Step form's schema picker between:
//   - "from skill" badge (skill provides a default schema → one-line badge)
//   - full <select> picker (user clicked Override, or skill has no default)
//
// When the badge is showing, the underlying <select name="json_schema_id">
// is intentionally left blank (its DOM value is ""). The server-side Step
// model's before_validation hook fills it in from skill.default_json_schema
// so the persisted config["json_schema_id"] matches what the badge shows.
// Override flips to the picker and lets the form send whatever the user
// chooses (including "None") explicitly.
export default class extends Controller {
  static targets = ["badge", "picker", "modeInput"]
  static values = { overridden: Boolean }

  override(event) {
    event.preventDefault()
    this.overriddenValue = true
    if (this.hasModeInputTarget) this.modeInputTarget.value = "override"
    if (this.hasBadgeTarget) this.badgeTarget.style.display = "none"
    if (this.hasPickerTarget) this.pickerTarget.style.display = ""
  }

  restoreDefault(event) {
    event.preventDefault()
    this.overriddenValue = false
    if (this.hasModeInputTarget) this.modeInputTarget.value = "inherit"
    const select = this.element.querySelector("select[name='json_schema_id']")
    if (select) select.value = ""
    if (this.hasPickerTarget) this.pickerTarget.style.display = "none"
    if (this.hasBadgeTarget) this.badgeTarget.style.display = ""
  }
}
