---
status: shipped
date: 2026-07-10
depends_on: [spec-001, spec-006, adr-001, adr-002]
---

# Spec 008: Command-palette site search (`Flicker.palette`)

The Algolia-DocSearch / `cmdk` experience for Ash apps: press ⌘K anywhere,
a fullscreen/centred overlay opens, type to search across your resources,
arrow to a result, Enter to go there. Prior art: Algolia DocSearch,
`cmdk`/kbar (React), CommandBar. Nothing owns this niche for LiveView, and
Flicker already has every ingredient — this spec is deliberately **thin
composition, not new machinery**: controlled mode (ADR-005) + a federated
provider (ADR-001) + `activate_with_keyboard` (Spec 006) + theme parts
(ADR-002) arranged into one blessed component.

Important scope distinction vs Algolia: Flicker searches your **Ash
resources** (records, actor-scoped), not crawled static page content.
"Search my hexdocs prose" is a provider someone could write; it is not this
spec.

## Scope

- **`Flicker.palette/1`** — a function component wrapping the same core as
  `Flicker.select/1`, presented as a modal overlay: backdrop, centred
  panel, large search input, result list, footer with kbd hints
  (↑↓ navigate · ↵ select · esc close). Opens via
  `activate_with_keyboard` (default `"mod+k"`) and/or an
  `open`/`on_close` controlled API so hosts can trigger it from a navbar
  button.
- **Overlay theme parts** ([ADR-002](../adrs/adr-002-rendering-via-slots-and-theme-map.md)):
  `backdrop`, `panel`, `palette-input`, `group-header`, `footer`,
  `kbd-hint` — added to `Flicker.Theme` with all presets, so restyling the
  palette is the same class-map exercise as restyling a select. A host
  should get from default to on-brand fullscreen search by overriding
  theme keys, no forking.
- **Grouped results.** Federated search wants results grouped by kind
  ("Clients", "Workers", "Documents" — DocSearch's section headers).
  `%Flicker.Result{}` gains an optional `group` field; the core renders
  contiguous group headers when results carry it. Ungrouped providers
  render exactly as today — `group` is additive, not breaking.
- **Navigate-on-select.** A palette selection usually means "go there":
  an `on_select` navigation convention where the provider puts a path in
  `result.meta.href` and the palette issues `JS.navigate`/`push_navigate`;
  hosts can still take the raw `on_select` for custom actions.
- **Overlay behaviour**: focus trapped in the panel while open; focus
  returns to the previously focused element on close; `Escape` closes
  (after the Spec 001 two-stage escape inside the input); background
  scroll locked; `role="dialog"` + `aria-modal` semantics coordinated with
  [Spec 007](./spec-007-screen-reader-support.md).
- **Playground page** ([Spec 005](./spec-005-dev-playground.md)): a
  federated palette over the whole `Dev.Music` domain — the demo that
  sells the library.

## Non-goals

- Crawling/indexing site content (that's Algolia's product; Flicker
  searches resources through providers).
- Command execution (kbar-style "run an action") — results are records to
  navigate to; actions-as-results is a provider recipe, maybe a later spec.
- Recent searches / frecency ranking — open question below.
- A hosted/search-as-a-service anything.

## Design

`Flicker.palette/1` renders the overlay chrome and embeds the same internal
LiveComponent as `Flicker.select/1` in controlled mode — one core, two
presentations. The overlay chrome (backdrop/panel/focus trap/scroll lock)
is palette-specific markup + a small amount of colocated-hook JS
([ADR-007](../adrs/adr-007-colocated-js-hook.md)); the search behaviour is
untouched Spec 001 machinery. If implementing this reveals palette-only
branches inside the core component, that's a smell — the seam belongs in
the wrapper.

Group ordering follows the provider's result order (providers own ranking;
the palette never re-sorts).

**As implemented:** `Flicker.palette/1` is a thin function component (no
form-field mode — controlled only) delegating to a new internal
`Flicker.Components.Palette` LiveComponent, which owns the overlay's
open/closed state and nests `Flicker.Components.Select` — the exact same
core `Flicker.select/1` runs — in controlled mode with an internal
`navigate_on_select: true` assign. Two additive, non-branching seams
landed in the core to make that possible without any "am I a palette"
conditionals: `Flicker.Result.group` (contiguous group-header rendering,
data-driven) and the `navigate_on_select` assign (`meta.href` +
`push_navigate/2`, also data/assign-driven — `Flicker.select/1` never
sets it). `open`/`on_close` reconcile with the host via edge-detection: a
change in the host's `open` value is adopted on the next render either
direction, while the component is otherwise free to open/close itself
(the `mod+k` chord, `Escape`, backdrop click) and always fires `on_close`
so host-side state never drifts.

## Acceptance criteria

- A host adds a working ⌘K site search with one component tag plus a
  federated provider module — nothing else.
- The palette is restylable to "fullscreen on-brand search" purely via
  theme overrides (prove it with a second themed variant in the playground).
- Group headers render from `result.group`; a groupless provider renders
  identically to today's flat list.
- Selecting a result with `meta.href` navigates; focus and scroll state
  restore correctly on close (including after navigation back).
- Keyboard map from Spec 001 holds inside the palette; focus trap and
  dialog semantics pass the Spec 007 axe/manual checks.
- Works with both an Ash federated provider and a pure-Elixir provider
  ([ADR-006](../adrs/adr-006-core-depends-only-on-provider.md)).

## Resolved questions

- **`group`: a `Result` field, not a provider callback.** A field keeps
  the shape uniform with `:value`/`:label`/`:sublabel`/`:meta` — no
  extra behaviour callback for the common case, and a provider that
  wants computed group labels can already do that in its own `search/2`
  before building each `Result`. `Flicker.Result.t()`'s `:group` defaults
  to `nil`, so this is additive: a groupless provider's rendering is
  untouched (covered by `Flicker.SelectGroupTest` and
  `Flicker.PaletteTest`).

## Open questions

- Recent searches / empty-state content (DocSearch shows recents before
  you type): ship a `:empty_state` slot only, or an optional recents
  mechanism (needs client-side storage — localStorage via the hook)?
  Not implemented in this pass — the palette accepts no `:empty_state`
  slot yet, it falls back to the core's existing `:no_results` message.
- Facet syntax (Spec 003) inside the palette from day one, or after both
  ship? Not implemented in this pass — `Flicker.palette/1` accepts and
  forwards `facets`, so it works today, but it hasn't been exercised
  end-to-end in the playground.
