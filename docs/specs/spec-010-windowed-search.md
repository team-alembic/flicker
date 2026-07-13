---
status: shipped
date: 2026-07-11
depends_on: [spec-001, spec-004, adr-003, adr-007]
---

# Spec 010: Windowed search — infinite scroll in the combobox

Opt-in pagination for the results listbox: scrolling near the bottom loads
the next window and appends it, so a picker over a large population can be
*browsed*, not only narrowed. Applies to `Flicker.select` (and therefore
the palette); `Flicker.search` lists no records and is unaffected.

**This deliberately changes a default we chose on purpose.** The shipped
behaviour — `limit + 1`, "keep typing to narrow" — encodes the view that
for a typeahead, narrowing *is* the interaction. That stays the default.
Windowing exists for the cases where it's genuinely wrong: browsing-shaped
populations (pick from ~200 mostly-unfamiliar options where the user
doesn't know what to type), and pickers used as "scan the list" UIs.
Enabling it is a UX decision the host makes per component, not a new
global default.

## Scope

- **`paginate` attr** on `Flicker.select/1` (default `false`). When off,
  behaviour is exactly today's. When on: the "keep typing to narrow" hint
  is replaced by windowed loading — reaching the end of the listbox loads
  the next `limit`-sized window and appends.
- **Provider contract extension — additive, not breaking.** `search/2`
  opts gain a documented `:offset` (non-negative integer, default 0).
  Providers that ignore it keep working (they always return the first
  window; core detects no-progress and stops asking — a provider must
  never be able to cause an infinite request loop). `AshResource`
  implements it via `Ash.Query.offset/2`; `Static` implements it with
  `Enum.slice/3`. `has_more` remains the `limit + 1` probe per window.
- **Loading trigger in the colocated hook** ([ADR-007](../adrs/adr-007-colocated-js-hook.md)):
  an IntersectionObserver on a sentinel row at the listbox tail pushes a
  `load-more` event when it becomes visible; a scroll-position fallback is
  acceptable if the observer proves awkward inside the overflow container.
  No npm dependency.
- **Window lifecycle**: a new query (or facet-context change) resets to
  window 0 and scrolls the listbox to the top; stale-result cancellation
  applies per window (a late window N response for a superseded query is
  dropped, and a late window N for the *current* query must append in
  order or be re-requested — never interleave). While a window loads, a
  themed `loading-more` row renders at the tail.
- **Keyboard + ARIA**: `ArrowDown` on the last loaded option triggers the
  same `load-more` (keyboard users get parity with scrollers, per the
  Spec 001 no-wrap rule the highlight just waits at the end until the
  window arrives); the live region announces appended counts
  ("20 more results, 60 total" — message-keyed per
  [ADR-009](../adrs/adr-009-messages-module-for-user-facing-text.md));
  `aria-busy` on the listbox while a window loads.
- **Bounds**: `max_windows` (or a total-results cap) so an unbounded
  scroll cannot grow the DOM/assigns without limit; on hitting the cap the
  tail row shows the narrow hint — windowing degrades *into* the existing
  philosophy rather than fighting it.
- **Playground page**: a paginated select over the full artist population
  (seed count raised if needed to make scrolling meaningful), including
  the slow provider so the loading-more row is observable.

## Non-goals

- Bidirectional/virtualised windowing (dropping earlier windows and
  re-fetching upward). Append-only with a cap is v1; virtualisation is a
  follow-up only if a real consumer hits the cap in practice.
- Pagination UI (page numbers, next/prev) — this is infinite scroll only.
- Keyset/cursor pagination in the contract. `:offset` is the v1 shape —
  simple, supported by both built-in providers, and honest about its
  consistency caveat (a record inserted mid-scroll can shift a window).
  Cursor support would be an additive second opt (`:after`) later, not a
  change to this one.
- `Flicker.search` (no record list) — nothing to window.

## Design

The component tracks `window :: non_neg_integer()` and accumulates
`results` across windows for the current query; everything else reuses the
existing async search plumbing — `load-more` runs the same
`run_record_search/2` path with `offset: window * limit`, and the append
happens where results are assigned today. The hook's sentinel/observer is
palette-compatible for free (same listbox markup). Selected-option
exclusion in multi-select mode applies per accumulated result set.

Provider capability detection is behavioural, not declared: core compares
a window's first result against the previous window's — an identical
window means the provider ignored `:offset`, so core marks the list
complete and renders the narrow hint. Documented on the behaviour.

## Acceptance criteria

- `paginate={false}` (default) renders byte-identical markup and issues
  identical provider calls to today — covered by a regression test.
- Scrolling to the tail appends the next window exactly once per
  crossing; a query keystroke mid-load discards the in-flight window and
  restarts at window 0.
- `ArrowDown` at the last option loads the next window and the highlight
  continues into it when it arrives.
- A provider that ignores `:offset` gets exactly two windows requested
  (probe + detection), then the list is marked complete — no request loop.
- Append announcements are message-keyed and reflect the latest query
  only; `aria-busy` toggles around each window load.
- At `max_windows` the tail renders the keep-typing hint.
- Works against `Static` (offset via slice) and `AshResource` (offset via
  `Ash.Query.offset/2`), each covered by tests; the playground page
  demonstrates both fast and slow providers.

## Open questions — resolved

- Default `max_windows`: **10** (≈200 results at the default `limit` of
  25) — beyond that, narrowing beats scrolling for any human.
- Should the palette default `paginate` on? **No.** `Flicker.palette/1`
  gains the same `paginate`/`max_windows` attrs (passed straight through
  to the nested `Flicker.Components.Select`) but defaults `paginate` to
  `false`, same as `Flicker.select/1` — consistency beats cleverness
  until a consumer asks.
- Does `load-more`-on-`ArrowDown` need debouncing? **Yes, one in-flight
  window at a time.** The server ignores a `load-more` event while a
  window is already loading or the list is complete; a held `ArrowDown`
  key-repeats the event, but only the first one past each completed
  fetch does anything — queued keypresses collapse rather than queuing a
  request each.
