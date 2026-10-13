import { Controller } from "@hotwired/stimulus"

// Draws how much is on your plate onto the tab's icon, and keeps the number
// right: every page arrives with the current one, a status change pushes a
// fresh one over a Turbo Stream, and a tab left open in the background asks
// again every so often — so a glance along the tab bar is enough.
export default class extends Controller {
  static targets = ["count"]
  static values = {
    open: Number,
    inProgress: Number,
    url: String,
    interval: { type: Number, default: 60_000 }
  }

  connect() {
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
    // Coming back to the tab is the moment the number has to be right.
    this.onVisible = () => { if (document.visibilityState === "visible") this.refresh() }
    document.addEventListener("visibilitychange", this.onVisible)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.onVisible)
  }

  // Both fire once on connect, and again when a poll changes a value.
  openValueChanged() { this.draw() }
  inProgressValueChanged() { this.draw() }

  async refresh() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!response.ok || !response.headers.get("content-type")?.includes("json")) return

      const counts = await response.json()
      this.openValue = counts.open
      this.inProgressValue = counts.in_progress
    } catch {
      // Offline, or the session ended. The next poll will try again.
    }
  }

  draw() {
    const total = this.openValue + this.inProgressValue

    this.updatePill(total)
    this.updateTitle(total)
    total > 0 ? this.setIcon(this.render(total)) : this.restoreIcon()
  }

  updatePill(total) {
    if (!this.hasCountTarget) return

    this.countTarget.textContent = total
    this.countTarget.title = `${this.openValue} open ticket${this.openValue === 1 ? "" : "s"}, ${this.inProgressValue} in progress`
    this.countTarget.classList.toggle("hidden", total === 0)
  }

  updateTitle(total) {
    const bare = document.title.replace(/^\(\d+\+?\)\s*/, "")
    document.title = total > 0 ? `(${total}) ${bare}` : bare
  }

  // The red disc from /icon.svg with the number on it. Past 99 the digits
  // stop fitting, and "a lot" is all that number was ever going to say.
  render(total) {
    const size = 64
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = size
    const ctx = canvas.getContext("2d")

    ctx.fillStyle = "red"
    ctx.beginPath()
    ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2)
    ctx.fill()

    const label = total > 99 ? "99+" : String(total)
    const fontSize = { 1: 46, 2: 38 }[label.length] || 28
    ctx.fillStyle = "white"
    ctx.font = `bold ${fontSize}px system-ui, -apple-system, sans-serif`
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillText(label, size / 2, size / 2 + 2)

    return canvas.toDataURL("image/png")
  }

  get links() {
    return Array.from(document.querySelectorAll("link[rel='icon']"))
  }

  setIcon(href) {
    this.links.forEach((link) => {
      // Remembered once, so a redraw after a stream replaces this element
      // doesn't mistake an earlier drawing for the real icon.
      link.dataset.originalHref ??= link.getAttribute("href")
      link.dataset.originalType ??= link.getAttribute("type") || ""
      link.href = href
      link.type = "image/png"
    })
  }

  restoreIcon() {
    this.links.forEach((link) => {
      if (link.dataset.originalHref === undefined) return

      link.href = link.dataset.originalHref
      link.dataset.originalType ? (link.type = link.dataset.originalType) : link.removeAttribute("type")
    })
  }
}
