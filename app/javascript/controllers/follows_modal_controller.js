import { Controller } from "@hotwired/stimulus"

// Drives the Following / Followers modal on the profile page.
// Usage:
//   <button data-action="click->follows-modal#open"
//           data-url="/u/jane/followers"
//           data-title="Followers">23 followers</button>
export default class extends Controller {
  static targets = ["panel", "title", "content"]

  // Localized strings supplied from the view via data-follows-modal-*-value.
  static values = { loading: String, error: String }

  async open(event) {
    const url   = event.currentTarget.dataset.url
    const title = event.currentTarget.dataset.title

    // Show modal with loading state immediately
    this.titleTarget.textContent   = title
    this.contentTarget.innerHTML   = `
      <div class="flex items-center justify-center py-16 text-zinc-500 text-sm">${this.loadingValue}</div>`
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.classList.add("flex")
    document.body.style.overflow = "hidden"

    try {
      const res = await fetch(url, {
        headers: { "X-CSRF-Token": this._csrf(), "Accept": "text/html" }
      })
      if (!res.ok) throw new Error("Failed to load")
      this.contentTarget.innerHTML = await res.text()
    } catch {
      this.contentTarget.innerHTML =
        `<p class="text-red-400 text-sm text-center py-12">${this.errorValue}</p>`
    }
  }

  closeBtn() { this._close() }

  // Swallow clicks inside the card so they don't reach the backdrop handler.
  // Does NOT call preventDefault, so button_to forms still submit normally.
  stopPropagation(event) {
    event.stopPropagation()
  }

  _close() {
    this.panelTarget.classList.add("hidden")
    this.panelTarget.classList.remove("flex")
    document.body.style.overflow = ""
    this.contentTarget.innerHTML = ""
  }

  _csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
