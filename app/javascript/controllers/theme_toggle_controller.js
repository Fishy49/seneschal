import { Controller } from "@hotwired/stimulus"

const HLJS_DARK = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css"
const HLJS_LIGHT = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css"

export default class extends Controller {
  static targets = ["thumb"]

  connect() {
    this.update()
  }

  toggle() {
    const current = document.documentElement.getAttribute("data-theme") || "dark"
    const next = current === "dark" ? "light" : "dark"
    document.documentElement.setAttribute("data-theme", next)
    localStorage.setItem("theme", next)
    document.getElementById("hljs-theme").href = next === "dark" ? HLJS_DARK : HLJS_LIGHT
    this.update()
  }

  update() {
    const light = document.documentElement.getAttribute("data-theme") === "light"
    this.thumbTarget.classList.toggle("is-light", light)
  }
}
