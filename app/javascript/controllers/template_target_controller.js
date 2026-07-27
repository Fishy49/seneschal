import { Controller } from "@hotwired/stimulus"

// The starter forms post to a project-nested route, so changing the project
// picker has to repoint the form rather than add a parameter.
export default class extends Controller {
  projectChanged(event) {
    const paths = JSON.parse(event.target.dataset.templateTargetPathsValue || "{}")
    const path = paths[event.target.value]
    if (path) this.element.action = path
  }
}
