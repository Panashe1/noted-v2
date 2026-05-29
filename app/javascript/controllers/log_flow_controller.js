import { Controller } from "@hotwired/stimulus"

// Manages the two-step Log Album modal:
//   Step 1: search → pick album from results
//   Step 2: preview album art + tracklist → fill in log form
export default class extends Controller {
  static targets = [
    "searchInput",   // <input> the user types into
    "searchResults", // container where search result HTML is injected
    "previewArea",   // container where server-rendered album preview is injected
    "logForm",       // the actual <form> to submit
    "step1",         // wrapper for step 1 (search)
    "step2",         // wrapper for step 2 (preview + form)
    "backBtn",       // back arrow button shown on step 2
    "modalTitle",    // heading text we swap between steps
    // Form hidden fields we auto-fill from the preview response
    "formTitle", "formArtist", "formYear", "formGenre",
    "formItunesId", "formCoverUrl", "formAppleUrl"
  ]

  connect() {
    this._debounceTimer = null
    this._searchAbort   = null
    this._previewAbort  = null
    this.reset()
  }

  // Called on keyup of the search input
  onSearchInput() {
    clearTimeout(this._debounceTimer)
    const q = this.searchInputTarget.value.trim()

    if (q.length < 2) {
      this.searchResultsTarget.innerHTML = ""
      return
    }

    this._debounceTimer = setTimeout(() => this._doSearch(q), 350)
  }

  async _doSearch(query) {
    if (this._searchAbort) this._searchAbort.abort()
    this._searchAbort = new AbortController()

    this.searchResultsTarget.innerHTML = `
      <p class="text-zinc-500 text-sm text-center py-4">Searching…</p>`

    try {
      const url = `/music/search?q=${encodeURIComponent(query)}`
      const res = await fetch(url, {
        headers: { "X-CSRF-Token": this._csrfToken() },
        signal: this._searchAbort.signal
      })
      if (!res.ok) throw new Error("Search failed")
      this.searchResultsTarget.innerHTML = await res.text()
    } catch (e) {
      if (e.name !== "AbortError") {
        this.searchResultsTarget.innerHTML = `
          <p class="text-red-400 text-sm text-center py-4">Search error. Please try again.</p>`
      }
    }
  }

  // Called when a search result button is clicked (data-action="click->log-flow#selectAlbum")
  async selectAlbum(event) {
    const itunesId = event.currentTarget.dataset.itunesId
    if (!itunesId) return

    if (this._previewAbort) this._previewAbort.abort()
    this._previewAbort = new AbortController()

    // Move to step 2 immediately, show loading state
    this.showStep2()
    this.previewAreaTarget.innerHTML = `
      <div class="flex items-center justify-center py-8 text-zinc-500 text-sm">Loading…</div>`

    try {
      const url = `/music/preview?itunes_id=${encodeURIComponent(itunesId)}`
      const res = await fetch(url, {
        headers: { "X-CSRF-Token": this._csrfToken() },
        signal: this._previewAbort.signal
      })
      if (!res.ok) throw new Error("Preview failed")

      this.previewAreaTarget.innerHTML = await res.text()
      this._populateFormFromPreview()
    } catch (e) {
      if (e.name !== "AbortError") {
        this.previewAreaTarget.innerHTML = `
          <p class="text-red-400 text-sm text-center py-4">Could not load album. Please go back and try again.</p>`
      }
    }
  }

  // Copy preview metadata into the actual log form hidden fields.
  // Reads values from the server-injected HTML via querySelector (avoids Stimulus
  // target registration timing issues with dynamically inserted elements).
  _populateFormFromPreview() {
    const area = this.previewAreaTarget

    // Read a value from the server-injected preview HTML by target name
    const fromPreview = (name) =>
      area.querySelector(`[data-log-flow-target="${name}"]`)?.value ?? ""

    if (this.hasFormTitleTarget)    this.formTitleTarget.value    = fromPreview("previewTitle")
    if (this.hasFormArtistTarget)   this.formArtistTarget.value   = fromPreview("previewArtist")
    if (this.hasFormYearTarget)     this.formYearTarget.value     = fromPreview("previewYear")
    if (this.hasFormGenreTarget)    this.formGenreTarget.value    = fromPreview("previewGenre")
    if (this.hasFormItunesIdTarget) this.formItunesIdTarget.value = fromPreview("itunesId")
    if (this.hasFormCoverUrlTarget) this.formCoverUrlTarget.value = fromPreview("coverUrl")
    if (this.hasFormAppleUrlTarget) this.formAppleUrlTarget.value = fromPreview("appleUrl")
  }

  // "Back" button on step 2
  goBack() {
    this.showStep1()
  }

  // "Enter details by hand" link — populate form fields as empty, skip to step 2
  showManual() {
    this.showStep2()
    this.previewAreaTarget.innerHTML = `
      <div class="space-y-3 mb-5">
        <input name="_manual_title" placeholder="Album title" required
               data-action="input->log-flow#syncManualTitle"
               class="w-full bg-sp-input rounded-md px-4 py-3 text-sm text-white placeholder-zinc-500 focus:outline-none focus:ring-1 focus:ring-white/30" />
        <div class="grid grid-cols-2 gap-3">
          <input name="_manual_artist" placeholder="Artist" required
                 data-action="input->log-flow#syncManualArtist"
                 class="bg-sp-input rounded-md px-4 py-3 text-sm text-white placeholder-zinc-500 focus:outline-none focus:ring-1 focus:ring-white/30" />
          <input name="_manual_year" placeholder="Year" type="number"
                 data-action="input->log-flow#syncManualYear"
                 class="bg-sp-input rounded-md px-4 py-3 text-sm text-white placeholder-zinc-500 focus:outline-none focus:ring-1 focus:ring-white/30" />
        </div>
        <input name="_manual_genre" placeholder="Genre (optional)"
               data-action="input->log-flow#syncManualGenre"
               class="w-full bg-sp-input rounded-md px-4 py-3 text-sm text-white placeholder-zinc-500 focus:outline-none focus:ring-1 focus:ring-white/30" />
      </div>`
  }

  // Keep hidden form fields in sync with manual inputs
  syncManualTitle(e)  { if (this.hasFormTitleTarget)  this.formTitleTarget.value  = e.target.value }
  syncManualArtist(e) { if (this.hasFormArtistTarget) this.formArtistTarget.value = e.target.value }
  syncManualYear(e)   { if (this.hasFormYearTarget)   this.formYearTarget.value   = e.target.value }
  syncManualGenre(e)  { if (this.hasFormGenreTarget)  this.formGenreTarget.value  = e.target.value }

  showStep1() {
    if (this.hasStep1Target)    this.step1Target.classList.remove("hidden")
    if (this.hasStep2Target)    this.step2Target.classList.add("hidden")
    if (this.hasBackBtnTarget)  this.backBtnTarget.classList.add("hidden")
    if (this.hasModalTitleTarget) this.modalTitleTarget.textContent = "Log an Album"
  }

  showStep2() {
    if (this.hasStep1Target)    this.step1Target.classList.add("hidden")
    if (this.hasStep2Target)    this.step2Target.classList.remove("hidden")
    if (this.hasBackBtnTarget)  this.backBtnTarget.classList.remove("hidden")
    if (this.hasModalTitleTarget) this.modalTitleTarget.textContent = "Confirm & Rate"
  }

  reset() {
    this.showStep1()
    if (this.hasSearchInputTarget)   this.searchInputTarget.value = ""
    if (this.hasSearchResultsTarget) this.searchResultsTarget.innerHTML = ""
    if (this.hasPreviewAreaTarget)   this.previewAreaTarget.innerHTML = ""
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
