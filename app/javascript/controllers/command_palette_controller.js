import { Controller } from "@hotwired/stimulus"

// ⌘K (Ctrl-K elsewhere) opens a search dialog. The searching itself is a
// Turbo frame hitting /search, so this only handles opening, closing,
// debouncing keystrokes and moving the highlight.
export default class extends Controller {
  static targets = ["dialog", "form", "input", "results"]

  connect() {
    this.index = 0
  }

  hotkey(event) {
    if (event.key !== "k" || !(event.metaKey || event.ctrlKey)) return

    event.preventDefault()
    this.dialogTarget.open ? this.close() : this.open()
  }

  open(event) {
    if (event) event.preventDefault()
    if (this.dialogTarget.open) return

    this.dialogTarget.showModal()
    this.inputTarget.select()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  // Clicking the backdrop lands on the dialog itself rather than its contents.
  clickOutside(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  closed() {
    this.index = 0
  }

  // One request per pause in typing, not one per keystroke.
  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.formTarget.requestSubmit(), 150)
  }

  navigate(event) {
    if (event.key === "ArrowDown") this.move(event, 1)
    else if (event.key === "ArrowUp") this.move(event, -1)
  }

  move(event, step) {
    const items = this.items
    if (items.length === 0) return

    event.preventDefault()
    this.index = (this.index + step + items.length) % items.length
    this.highlight()
    items[this.index].scrollIntoView({ block: "nearest" })
  }

  // Enter opens whatever is highlighted rather than reloading the search.
  follow(event) {
    event.preventDefault()
    this.items[this.index]?.click()
  }

  highlightFirst() {
    this.index = 0
    this.highlight()
  }

  highlight() {
    this.items.forEach((item, position) => {
      item.setAttribute("aria-selected", position === this.index)
    })
  }

  get items() {
    return Array.from(this.resultsTarget.querySelectorAll("[data-palette-item]"))
  }
}
