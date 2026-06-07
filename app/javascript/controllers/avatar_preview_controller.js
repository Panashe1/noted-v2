import { Controller } from "@hotwired/stimulus"

// Shows a live preview of a chosen avatar image before it is uploaded.
// Usage:
//   data-controller="avatar-preview"
//   data-avatar-preview-target="preview"      on the <img> that displays the preview
//   data-avatar-preview-target="placeholder"  on the fallback shown when no image yet (optional)
//   data-action="change->avatar-preview#update" on the file <input>
export default class extends Controller {
  static targets = ["preview", "placeholder"]

  update(event) {
    const file = event.target.files[0]
    if (!file) return

    // Release any object URL from a previous selection so we don't leak memory.
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = URL.createObjectURL(file)

    this.previewTarget.src = this.objectUrl
    this.previewTarget.classList.remove("hidden")
    if (this.hasPlaceholderTarget) this.placeholderTarget.classList.add("hidden")
  }

  disconnect() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  }
}
