import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

let sharedConsumer = null

function consumer() {
  if (!sharedConsumer) sharedConsumer = createConsumer()
  return sharedConsumer
}

function initials(email) {
  const local = email.split("@")[0]
  const parts = local.split(/[._-]+/).filter(Boolean)
  const letters = parts.length > 1 ? parts[0][0] + parts[1][0] : local.slice(0, 2)
  return letters.toUpperCase()
}

// Shows who else has this run open. Purely decorative: any failure here is
// swallowed so the run page and its Turbo stream keep working.
export default class extends Controller {
  static values = { runId: Number }
  static targets = ["roster"]

  connect() {
    try {
      this.subscription = consumer().subscriptions.create(
        { channel: "PresenceChannel", run_id: this.runIdValue },
        { received: (data) => this.render(data.viewers || []) }
      )
    } catch {
      this.subscription = null
    }
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe()
    this.subscription = null
  }

  render(viewers) {
    this.rosterTarget.replaceChildren(...viewers.map((email) => {
      const chip = document.createElement("span")
      chip.className =
        "inline-flex items-center justify-center w-6 h-6 rounded-full bg-surface-input border border-edge text-[0.625rem] font-semibold text-content-muted"
      chip.textContent = initials(email)
      chip.title = email
      return chip
    }))
    this.element.hidden = viewers.length === 0
  }
}
