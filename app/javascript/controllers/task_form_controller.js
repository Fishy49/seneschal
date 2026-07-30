import { Controller } from "@hotwired/stimulus"

// Keeps the workflow cards in sync with the chosen project. Every workflow is
// rendered and tagged with its project id; this hides the ones that do not
// belong, and clears a selection the new project no longer offers.
export default class extends Controller {
  static targets = ["projectSelect", "workflowCard", "noWorkflows"]

  connect() {
    this.projectChanged()
  }

  projectChanged() {
    const projectId = this.projectSelectTarget.value
    let visibleWorkflows = 0

    this.workflowCardTargets.forEach((card) => {
      // The draft card carries no project and is always on offer.
      const belongs = !card.dataset.projectId || card.dataset.projectId === projectId
      card.hidden = !belongs
      if (belongs && card.dataset.projectId) visibleWorkflows += 1

      if (!belongs) {
        const radio = card.querySelector("input[type=radio]")
        if (radio) radio.checked = false
      }
    })

    if (this.hasNoWorkflowsTarget) this.noWorkflowsTarget.hidden = visibleWorkflows > 0
  }
}
