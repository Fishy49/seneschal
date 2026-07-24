import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["thumb"]
  // Digest-stamped paths to the two vendored highlight.js themes, injected by
  // the layout so this controller never has to know an asset URL.
  static values = { darkCss: String, lightCss: String }

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

    this.update()
  }

  update() {
    const light = document.documentElement.getAttribute("data-theme") === "light"
    this.thumbTarget.classList.toggle("is-light", light)
  }
}
