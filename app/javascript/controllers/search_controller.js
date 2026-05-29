import { Controller } from "@hotwired/stimulus"

// Debounces a search input and auto-submits its form into a Turbo Frame.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this._timer = null
  }

  onInput() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._submit(), 300)
  }

  _submit() {
    this.element.requestSubmit()
  }
}
