import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  connect() {
    // Close modal on successful form submission (Turbo navigates away)
    document.addEventListener("turbo:before-visit", this._close.bind(this))
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this._close.bind(this))
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.classList.add("flex")
    document.body.style.overflow = "hidden"
  }

  close(event) {
    // Only close if clicking the backdrop (not the card inside)
    if (event && event.target !== event.currentTarget) return
    this._close()
  }

  closeBtn() {
    this._close()
  }

  // Swallow click events that originate inside the card so they never reach
  // the backdrop handler above. Does NOT call preventDefault, so forms still submit.
  stopPropagation(event) {
    event.stopPropagation()
  }

  _close() {
    this.panelTarget.classList.add("hidden")
    this.panelTarget.classList.remove("flex")
    document.body.style.overflow = ""
    // Reset the log-flow search state so next open starts fresh
    const logFlow = this.application.getControllerForElementAndIdentifier(
      this.panelTarget, "log-flow"
    )
    if (logFlow) logFlow.reset()
  }
}
