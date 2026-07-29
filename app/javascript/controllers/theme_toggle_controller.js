import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["thumb"]
  // Digest-stamped paths to the two vendored highlight.js themes, injected by
  // the layout so this controller never has to know an asset URL. persistUrl
  // is the account endpoint; present only when someone is signed in.
  static values = { darkCss: String, lightCss: String, persistUrl: String }

  connect() {
    this.update()
  }

  toggle() {
    const current = document.documentElement.getAttribute("data-theme") || "dark"
    const next = current === "dark" ? "light" : "dark"
    document.documentElement.setAttribute("data-theme", next)
    localStorage.setItem("theme", next)

    const themeLink = document.getElementById("hljs-theme")
    if (themeLink && this.hasDarkCssValue && this.hasLightCssValue) {
      themeLink.href = next === "dark" ? this.darkCssValue : this.lightCssValue
    }

    this.persist(next)
    this.update()
  }

  // Best-effort: the flip already happened locally; losing the write only
  // means the other devices keep the old theme.
  persist(theme) {
    if (!this.hasPersistUrlValue || !this.persistUrlValue) return

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.persistUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        ...(token ? { "X-CSRF-Token": token } : {})
      },
      body: JSON.stringify({ user: { theme } })
    }).catch(() => {})
  }

  update() {
    const light = document.documentElement.getAttribute("data-theme") === "light"
    this.thumbTarget.classList.toggle("is-light", light)
  }
}
