import { Controller } from "@hotwired/stimulus"

// Debounced search over the whole collection.
//
// Adapted from tsundoku's navbar_search_controller (a Rails Blocks component),
// keeping the mechanism — wait `debounce` ms, then point a turbo-frame at
// `url?q=…` and let Turbo swap the fragment in — and dropping its dropdown, its
// outside-click handler and its minimum length, none of which this page has any
// use for. The results are the page.
//
// Deliberately NOT nosh's client-side filter. That works there because nosh puts
// every recipe on one page, so the cards are already in the browser. This index
// is paged at 48, because 153 thumbnails is about 8MB, and filtering the rendered
// page would quietly hide every match on every other page. Searching on the
// server also puts the query in the URL, so a search survives a refresh, a
// reload and the back button.
export default class extends Controller {
  static targets = ["input", "frame", "clear"]
  static values = { url: String, debounce: { type: Number, default: 200 } }

  connect() {
    this.timeout = null
    this.toggleClear()
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  query() {
    clearTimeout(this.timeout)
    this.toggleClear()
    this.timeout = setTimeout(() => this.load(), this.debounceValue)
  }

  clear(event) {
    if (event) event.preventDefault()
    this.inputTarget.value = ""
    this.toggleClear()
    this.load()
    this.inputTarget.focus()
  }

  keydown(event) {
    if (event.key === "Escape") this.clear()
  }

  load() {
    const term = this.inputTarget.value.trim()
    const url = new URL(this.urlValue, window.location.origin)
    if (term) url.searchParams.set("q", term)

    // Turbo replaces the frame's contents, and because the frame advances
    // history the address bar follows along.
    this.frameTarget.src = url.pathname + url.search
  }

  toggleClear() {
    if (this.hasClearTarget) this.clearTarget.hidden = !this.inputTarget.value
  }
}
