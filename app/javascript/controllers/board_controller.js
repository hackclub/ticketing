import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Drag a card into another column to change its status. The card moves first
// and the request follows; if the request fails the card goes back where it
// came from, so the board never quietly disagrees with the database.
export default class extends Controller {
  static targets = ["card", "column", "dropzone", "count"]
  static values = { url: String }

  dragStart(event) {
    this.dragged = event.currentTarget
    this.origin = this.dragged.parentElement
    event.dataTransfer.effectAllowed = "move"
    // Firefox won't start a drag without something on the transfer.
    event.dataTransfer.setData("text/plain", this.dragged.dataset.ticketId)
    this.dragged.classList.add("is-dragging")
  }

  dragEnd() {
    this.dragged?.classList.remove("is-dragging")
    this.columnTargets.forEach((column) => column.classList.remove("is-over"))
  }

  dragOver(event) {
    if (!this.dragged) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.classList.add("is-over")
  }

  dragLeave(event) {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      event.currentTarget.classList.remove("is-over")
    }
  }

  drop(event) {
    if (!this.dragged) return

    event.preventDefault()
    const column = event.currentTarget
    column.classList.remove("is-over")

    const status = column.dataset.status
    const card = this.dragged
    const from = this.origin

    column.querySelector("[data-board-target='dropzone']").prepend(card)
    this.recount()

    this.save(card, status).catch(() => {
      from.prepend(card)
      this.recount()
    })
  }

  async save(card, status) {
    const response = await fetch(`${this.urlValue}/${card.dataset.ticketId}`, {
      method: "PATCH",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: new URLSearchParams({ "ticket[status]": status })
    })

    if (!response.ok) throw new Error(response.statusText)

    // The response carries the flash and anything else that moved with it.
    Turbo.renderStreamMessage(await response.text())
  }

  recount() {
    this.columnTargets.forEach((column) => {
      const count = column.querySelectorAll("[data-board-target='card']").length
      column.querySelector("[data-board-target='count']").textContent = count
    })
  }
}
