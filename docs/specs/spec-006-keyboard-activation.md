---
status: draft
date: 2026-07-10
depends_on: [spec-001, adr-007, adr-009]
---

# Spec 006: Keyboard activation (`activate_with_keyboard`)

A global keyboard shortcut that jumps focus into a Flicker search from
anywhere on the page — `activate_with_keyboard="mod+k"` and any Ash app has
a Cmd+K supersearch. Pure client-side sugar on top of the existing
component: the hook registers a document-level listener; matching the chord
focuses the input and opens the dropdown.

## Scope

- **`activate_with_keyboard` attr** taking a chord string:
  `+`-separated modifiers (`meta`, `ctrl`, `alt`, `shift`) plus one key
  matched against `KeyboardEvent.key`, with the alias **`mod`** = `meta` on
  macOS, `ctrl` elsewhere — so `"mod+k"` is the cross-platform Cmd/Ctrl+K.
- **Activation behaviour**: on chord match anywhere in the document —
  `preventDefault`, focus the search input, open the listbox. If the user
  is mid-typing in another text input, a modifier chord still activates
  (that's the point); bare-key chords (no modifier) are rejected at
  validation rather than silently hijacking typing.
- **Discoverability**: a themed `<kbd>` hint part rendered in the control
  (e.g. `⌘K`, platform-formatted), and `aria-keyshortcuts` on the input.
  Hint strings route through the messages module
  ([ADR-009](../adrs/adr-009-messages-module-for-user-facing-text.md)).
- **Registration hygiene**: listener registered on hook `mounted`, removed
  on `destroyed`; two components claiming the same chord logs a console
  warning and the first registration wins; activation is inert until the
  socket is connected (the dead-render rule,
  [ADR-005](../adrs/adr-005-form-field-mode-owns-hidden-inputs.md)).

## Non-goals

- A full command-palette overlay component (`Flicker.palette`) — open
  question below. This spec only gets focus into an *existing* rendered
  Flicker; hosts can already build supersearch by putting a controlled-mode
  Flicker with a federated provider inside their own modal.
- Multiple chords per component, chord sequences (`g` then `s`), or
  user-customisable rebinding.

## Design

All client-side, inside the colocated hook
([ADR-007](../adrs/adr-007-colocated-js-hook.md)) — no server round-trip to
activate. Chord parsing is a tiny pure JS function (unit-testable) that
normalises the attr string once at mount; invalid chords raise at Elixir
attr-validation time where possible (`mod+k` syntax is checkable
server-side) so misconfiguration fails loudly, not silently.

## Acceptance criteria

- `activate_with_keyboard="mod+k"` focuses + opens the component from
  anywhere on the page, on both macOS (⌘K) and Windows/Linux (Ctrl+K).
- The chord works while focus is in an unrelated text input; a bare-key
  chord (`"k"`) is rejected with a clear error.
- Unmounting the LiveView removes the listener (no activation on a page
  that no longer renders the component).
- Two components with the same chord: console warning, deterministic
  winner, no double-activation.
- The kbd hint renders platform-appropriate text and the input carries
  `aria-keyshortcuts`.
- Pressing the chord before the socket connects does nothing (and does not
  queue a stale activation for after connect).

## Open questions

- Does Flicker ship a `Flicker.palette` overlay variant (centred modal,
  backdrop, recent-searches) as the blessed supersearch, or stay a recipe
  in the playground + docs? Lean: recipe first, promote if every consumer
  builds the same modal.
- Should the chord also *close* (toggle) when the component is already
  focused?
