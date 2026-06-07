import { Controller } from "@hotwired/stimulus"

// Expand / collapse a line-clamped block on tap, swapping the toggle label.
// Toggles the `line-clamp-3` utility on the content element.
// Usage:
//   data-controller="clamp"
//   data-clamp-target="content"  on the clamped element (carries line-clamp-3)
//   data-clamp-target="toggle"   on the toggle button
//   data-action="click->clamp#toggle" on the toggle button
// Optional labels:
//   data-clamp-more-text-value="Read more"
//   data-clamp-less-text-value="See less"
export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = {
    moreText: { type: String, default: "Read more" },
    lessText: { type: String, default: "See less" }
  }

  toggle() {
    // classList.toggle returns true when the class was added (now clamped),
    // false when removed (now expanded) — drives the button label.
    const clamped = this.contentTarget.classList.toggle("line-clamp-3")
    this.toggleTarget.textContent = clamped ? this.moreTextValue : this.lessTextValue
  }
}
