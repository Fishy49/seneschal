import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "sidebar_projects_open"

export default class extends Controller {
  static targets = ["list", "icon"]

  connect() {
    const open = localStorage.getItem(STORAGE_KEY) === "true"
    this.listTarget.style.display = open ? "" : "none"
    this.iconTarget.textContent = open ? "\u25BE" : "\u25B6"
  }

  toggle() {
    const open = this.listTarget.style.display === "none"
    this.listTarget.style.display = open ? "" : "none"
    this.iconTarget.textContent = open ? "\u25BE" : "\u25B6"
    localStorage.setItem(STORAGE_KEY, open)
  }
}
