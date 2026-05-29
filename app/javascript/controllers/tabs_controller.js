import { Controller } from "@hotwired/stimulus"

// Minimal tabs controller — toggles panels, styles active/inactive tab buttons.
// Usage:
//   data-controller="tabs"
//   data-tabs-target="tab"   on each tab button
//   data-tabs-target="panel" on each content panel (same order as tabs)
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this._activate(0)
  }

  switch(event) {
    const index = this.tabTargets.indexOf(event.currentTarget)
    this._activate(index)
  }

  _activate(index) {
    this.tabTargets.forEach((tab, i) => {
      const active = i === index
      tab.classList.toggle("text-white",    active)
      tab.classList.toggle("bg-sp-card",    active)
      tab.classList.toggle("text-zinc-400", !active)
      tab.classList.toggle("bg-transparent",!active)
    })

    this.panelTargets.forEach((panel, i) => {
      panel.classList.toggle("hidden", i !== index)
    })
  }
}
