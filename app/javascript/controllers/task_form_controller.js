import { Controller } from "@hotwired/stimulus"

// Keeps the Workflow select in sync with the Project select. The ERB renders
// every workflow tagged with its project id; this narrows the list down and
// drops a selection that no longer belongs to the chosen project.
export default class extends Controller {
  static targets = ["projectSelect", "workflowSelect"]

  connect() {
    this.allOptions = Array.from(this.workflowSelectTarget.options).map((option) => option.cloneNode(true))
    this.projectChanged()
  }

  projectChanged() {
    const projectId = this.projectSelectTarget.value
    const previous = this.workflowSelectTarget.value

    const matching = this.allOptions.filter((option) => !option.value || option.dataset.projectId === projectId)
    this.workflowSelectTarget.replaceChildren(...matching.map((option) => option.cloneNode(true)))

    this.workflowSelectTarget.value = matching.some((option) => option.value === previous) ? previous : ""
  }
}
