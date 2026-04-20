import { Turbo } from "@hotwired/turbo-rails"

Turbo.StreamActions.assistant_navigate = function () {
  const path = this.getAttribute("path")
  if (path) Turbo.visit(path)
}

Turbo.StreamActions.assistant_focus_input = function () {
  const target = this.getAttribute("target")
  if (target) {
    const el = document.getElementById(target)
    if (el) el.focus()
  }
}
