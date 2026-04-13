import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "tree", "empty", "groupToggle", "moduleBtn"]
  static values = {
    tree: Array,
    modules: Array,
    fileIndex: Object,
    searchUrl: String
  }

  connect() {
    this.groupedByModule = false
    this.activeModule = null
    this.searchTimeout = null
    this.renderTree()
  }

  onSearch() {
    clearTimeout(this.searchTimeout)
    this.searchTimeout = setTimeout(() => this.filterTree(), 150)
  }

  filterTree() {
    const query = this.searchTarget.value.toLowerCase().trim()

    if (query) {
      this.clearModuleHighlight()
      this.activeModule = null
    }

    const nodes = this.treeTarget.querySelectorAll("[data-path]")
    let anyVisible = false

    nodes.forEach(node => {
      const path = node.dataset.path.toLowerCase()
      const summary = (node.dataset.summary || "").toLowerCase()
      const visible = !query || path.includes(query) || summary.includes(query)
      node.style.display = visible ? "" : "none"
      if (visible) anyVisible = true
    })

    this.updateDirVisibility(query)
    if (query) this.expandToVisible()
    this.emptyTarget.style.display = anyVisible || !query ? "none" : ""
  }

  toggleGrouping() {
    this.groupedByModule = !this.groupedByModule
    this.activeModule = null
    this.groupToggleTarget.textContent = this.groupedByModule
      ? "Group by directory"
      : "Group by module"
    this.renderTree()
  }

  filterByModule(event) {
    const moduleName = event.currentTarget.dataset.module
    this.searchTarget.value = ""

    // Toggle: clicking the same module deselects it
    if (this.activeModule === moduleName) {
      this.activeModule = null
      this.clearModuleHighlight()
      this.showAllNodes()
      return
    }

    this.activeModule = moduleName
    this.highlightModule(moduleName)

    const nodes = this.treeTarget.querySelectorAll("[data-path]")
    let anyVisible = false

    nodes.forEach(node => {
      const visible = node.dataset.module === moduleName
      node.style.display = visible ? "" : "none"
      if (visible) anyVisible = true
    })

    this.updateDirVisibility(true)
    this.expandToVisible()
    this.emptyTarget.style.display = anyVisible ? "none" : ""
  }

  toggleDir(event) {
    const dirEl = event.currentTarget.closest("[data-dir]")
    if (!dirEl) return
    const content = dirEl.querySelector("[data-dir-content]")
    const arrow = dirEl.querySelector("[data-arrow]")
    if (!content) return

    const collapsed = content.style.display === "none"
    content.style.display = collapsed ? "" : "none"
    if (arrow) arrow.textContent = collapsed ? "▼" : "▶"
  }

  // --- Module highlight ---

  highlightModule(name) {
    this.moduleBtnTargets.forEach(btn => {
      if (btn.dataset.module === name) {
        btn.classList.add("bg-accent/10", "border-accent", "border")
      } else {
        btn.classList.remove("bg-accent/10", "border-accent", "border")
      }
    })
  }

  clearModuleHighlight() {
    this.moduleBtnTargets.forEach(btn => {
      btn.classList.remove("bg-accent/10", "border-accent", "border")
    })
  }

  // --- Visibility helpers ---

  showAllNodes() {
    this.treeTarget.querySelectorAll("[data-path]").forEach(n => n.style.display = "")
    this.treeTarget.querySelectorAll("[data-dir]").forEach(d => d.style.display = "")
    this.emptyTarget.style.display = "none"
    // Re-collapse all
    this.collapseAll()
  }

  updateDirVisibility(hasFilter) {
    // Walk dirs bottom-up: hide dirs with no visible children
    const dirs = Array.from(this.treeTarget.querySelectorAll("[data-dir]"))
    dirs.reverse().forEach(dir => {
      const dirPath = dir.dataset.dir
      // Check for visible direct file children
      const hasVisibleFile = Array.from(dir.querySelectorAll(":scope > [data-dir-content] > [data-path]"))
        .some(n => n.style.display !== "none")
      // Check for visible nested dir children
      const hasVisibleSubdir = Array.from(dir.querySelectorAll(":scope > [data-dir-content] > [data-dir-wrapper] > [data-dir]"))
        .some(d => d.style.display !== "none")
      dir.style.display = (hasVisibleFile || hasVisibleSubdir || !hasFilter) ? "" : "none"
    })
  }

  expandToVisible() {
    // Expand dirs that contain visible files
    this.treeTarget.querySelectorAll("[data-path]").forEach(node => {
      if (node.style.display === "none") return
      let parent = node.closest("[data-dir-content]")
      while (parent) {
        parent.style.display = ""
        const arrow = parent.closest("[data-dir]")?.querySelector("[data-arrow]")
        if (arrow) arrow.textContent = "▼"
        parent = parent.parentElement?.closest("[data-dir-content]")
      }
    })
  }

  collapseAll() {
    this.treeTarget.querySelectorAll("[data-dir-content]").forEach(el => {
      el.style.display = "none"
    })
    this.treeTarget.querySelectorAll("[data-arrow]").forEach(el => {
      el.textContent = "▶"
    })
  }

  // --- Rendering ---

  renderTree() {
    if (this.groupedByModule) {
      this.renderByModule()
    } else {
      this.renderByDirectory()
    }
  }

  renderByDirectory() {
    const tree = this.treeValue
    const fileIndex = this.fileIndexValue

    // Build a nested directory structure
    const root = { dirs: {}, files: [] }
    tree.forEach(f => {
      const parts = f.path.split("/")
      const fileName = parts.pop()
      let node = root
      parts.forEach(part => {
        if (!node.dirs[part]) node.dirs[part] = { dirs: {}, files: [] }
        node = node.dirs[part]
      })
      node.files.push(f)
    })

    const html = this.renderNestedDir(root, "", fileIndex, true)
    this.treeTarget.innerHTML = html
    this.collapseAll()
  }

  renderNestedDir(node, path, fileIndex, isRoot) {
    let html = ""

    // Sort dirs and files
    const dirNames = Object.keys(node.dirs).sort()
    const files = node.files.sort((a, b) => a.path.localeCompare(b.path))

    // Render subdirectories
    dirNames.forEach(name => {
      const dirPath = path ? `${path}/${name}` : name
      const subNode = node.dirs[name]
      const fileCount = this.countFiles(subNode)

      const inner = this.renderNestedDir(subNode, dirPath, fileIndex, false)

      if (isRoot) {
        html += `<div class="border-b border-edge last:border-b-0">
          <div data-dir="${this.escapeAttr(dirPath)}">
            <div class="flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-surface-input"
                 data-action="click->code-tree#toggleDir">
              <span data-arrow class="text-xs text-content-muted w-3">▶</span>
              <span class="text-sm font-medium text-content-muted">${this.escapeHtml(name)}/</span>
              <span class="text-xs text-content-muted ml-auto">${fileCount}</span>
            </div>
            <div data-dir-content style="display:none">${inner}</div>
          </div>
        </div>`
      } else {
        html += `<div data-dir-wrapper>
          <div data-dir="${this.escapeAttr(dirPath)}">
            <div class="flex items-center gap-2 px-3 py-1.5 cursor-pointer hover:bg-surface-input"
                 style="padding-left:${this.indent(dirPath)}px"
                 data-action="click->code-tree#toggleDir">
              <span data-arrow class="text-xs text-content-muted w-3">▶</span>
              <span class="text-sm text-content-muted">${this.escapeHtml(name)}/</span>
              <span class="text-xs text-content-muted ml-auto">${fileCount}</span>
            </div>
            <div data-dir-content style="display:none">${inner}</div>
          </div>
        </div>`
      }
    })

    // Render files
    files.forEach(f => {
      html += this.renderFileNode(f, fileIndex[f.path], path)
    })

    return html
  }

  countFiles(node) {
    let count = node.files.length
    Object.values(node.dirs).forEach(sub => { count += this.countFiles(sub) })
    return count
  }

  indent(path) {
    const depth = path.split("/").length
    return 12 + depth * 16
  }

  renderByModule() {
    const modules = this.modulesValue
    const fileIndex = this.fileIndexValue
    let html = ""

    modules.forEach(mod => {
      const files = (mod.files || []).map(path => {
        const entry = this.treeValue.find(f => f.path === path)
        return entry || { path, type: "file", size: 0, dir: ".", ext: "" }
      })

      html += `<div class="border-b border-edge last:border-b-0">
        <div data-dir="${mod.name}" class="group">
          <div class="flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-surface-input"
               data-action="click->code-tree#toggleDir">
            <span data-arrow class="text-xs text-content-muted w-3">▶</span>
            <span class="font-medium text-sm text-accent">${this.escapeHtml(mod.name)}</span>
            <span class="text-xs text-content-muted">${mod.description || ""}</span>
            <span class="text-xs text-content-muted ml-auto">${files.length} files</span>
          </div>
          <div data-dir-content style="display:none">
            ${files.map(f => this.renderFileNode(f, fileIndex[f.path])).join("")}
          </div>
        </div>
      </div>`
    })

    this.treeTarget.innerHTML = html
  }

  renderFileNode(file, info, parentPath) {
    const summary = info?.summary || ""
    const moduleName = info?.module || ""
    const lang = info?.language || file.ext || ""
    const fileName = file.path.split("/").pop()
    const depth = file.path.split("/").length
    const pl = parentPath !== undefined ? `padding-left:${12 + depth * 16}px` : "padding-left:2rem"

    return `<div data-path="${this.escapeAttr(file.path)}"
                 data-summary="${this.escapeAttr(summary)}"
                 data-module="${this.escapeAttr(moduleName)}"
                 class="flex items-center gap-2 pr-3 py-1.5 hover:bg-surface-input text-sm"
                 style="${pl}">
      <span class="text-content-muted text-xs w-8 text-right shrink-0">${this.langBadge(lang)}</span>
      <span class="text-content truncate">${this.escapeHtml(fileName)}</span>
      <span class="text-xs text-content-muted truncate flex-1">${this.escapeHtml(summary)}</span>
    </div>`
  }

  langBadge(lang) {
    if (!lang) return ""
    const short = {
      ruby: "rb", javascript: "js", typescript: "ts", python: "py",
      html: "html", css: "css", markdown: "md", yaml: "yml", json: "json",
      erb: "erb", sql: "sql", shell: "sh", go: "go", rust: "rs"
    }
    return `<span class="inline-block px-1 py-0 rounded text-[0.625rem] bg-surface-input text-content-muted">${short[lang] || lang}</span>`
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  escapeAttr(str) {
    return (str || "").replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
