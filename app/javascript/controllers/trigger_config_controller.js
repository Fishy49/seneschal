import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "type", "cronPanel", "watchPanel",
    "cronPreset", "cronCustom",
    "repoUrl", "branch", "loadBranchesBtn", "branchStatus"
  ]
  static values = { branchesUrl: String }

  connect() {
    this.typeChanged()
    this.presetChanged()
  }

  // The trigger is a row of radios, so read whichever is checked rather than
  // the first target.
  get selectedType() {
    const checked = this.typeTargets.find((input) => input.checked)
    return checked ? checked.value : this.typeTargets[0]?.value
  }

  typeChanged() {
    const type = this.selectedType
    this.cronPanelTarget.hidden = type !== "cron"
    this.watchPanelTarget.hidden = type !== "github_watch"
  }

  presetChanged() {
    if (!this.hasCronPresetTarget) return
    this.cronCustomTarget.hidden = this.cronPresetTarget.value !== "custom"
  }

  async loadBranches() {
    const url = this.repoUrlTarget.value.trim()
    if (!url) {
      this.branchStatusTarget.textContent = "Enter a repo URL first."
      return
    }

    const original = this.loadBranchesBtnTarget.textContent
    this.loadBranchesBtnTarget.textContent = "Loading..."
    this.loadBranchesBtnTarget.disabled = true
    this.branchStatusTarget.textContent = ""

    try {
      const u = new URL(this.branchesUrlValue, window.location.origin)
      u.searchParams.set("repo_url", url)
      const response = await fetch(u, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()

      if (!response.ok) {
        this.branchStatusTarget.textContent = data.error || "Failed to load branches."
        return
      }

      this.populateBranches(data.branches || [])
    } catch (e) {
      this.branchStatusTarget.textContent = `Failed to load branches: ${e.message}`
    } finally {
      this.loadBranchesBtnTarget.textContent = original
      this.loadBranchesBtnTarget.disabled = false
    }
  }

  populateBranches(branches) {
    const select = this.branchTarget
    const currentValue = select.value || select.dataset.initialValue || ""
    select.innerHTML = ""

    if (!branches.length) {
      this.branchStatusTarget.textContent = "No branches returned."
      return
    }

    for (const name of branches) {
      const opt = document.createElement("option")
      opt.value = name
      opt.textContent = name
      if (name === currentValue) opt.selected = true
      select.appendChild(opt)
    }
    select.disabled = false
    this.branchStatusTarget.textContent = `Loaded ${branches.length} branches.`
  }
}
