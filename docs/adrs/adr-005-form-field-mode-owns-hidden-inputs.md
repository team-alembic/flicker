---
status: accepted
date: 2026-07-10
---

# ADR-005: Form-field mode owns its hidden inputs and the `_unused_` recovery marker; controlled mode is a separate first-class mode

## Context

Integrating a custom select with `<.form>` has two hard-won subtleties from
the origin implementation (mechanics preserved in the
[extraction notes](../reference/extraction-notes.md)):

1. The component must emit the hidden input(s) carrying the selected
   value(s), plus the `_unused_<field>` marker, so the required-field error
   does not fire before the field is engaged and so LiveSocket-reconnect
   form recovery restores state correctly.
2. Not every picker lives in a form — some emit a selection event and no
   params at all.

A dead-render lesson rides along from the origin app: interacting with markup
before the LiveView joins drops the event, and the first connected render
wipes the value.

## Decision

Two explicit modes:

- **Form-field mode** (`field={f[:client_id]}`): Flicker owns the hidden
  input(s) — `name[]` array inputs for multi-select — and the
  `_unused_<field>` marker logic, ported as-is from the proven origin
  implementation. The AshPhoenix.Form `attach/2` merge hook ships as an
  **optional adapter**, so `ash_phoenix` is not a hard dependency.
- **Controlled mode** (no `field`): the component emits `on_select` (or a
  message to the parent) and renders no form inputs.

In both modes, interactive controls are disabled until `connected?/1` — the
component guards this itself so consumers don't re-learn PR #493.

Rejected: form-mode only (excludes non-form pickers), leaving hidden-input
management to the host (every consumer re-derives the `_unused_` subtlety
and most get it wrong), hard-depending on AshPhoenix.Form (needless dep for
controlled mode and plain Phoenix forms).

## Consequences

- The `_unused_` logic needs its own regression tests; it is the least
  obvious behaviour in the library and the easiest to break in refactors.
- The mode is inferred from the presence of `field`, so attr validation must
  reject nonsensical combinations (e.g. `on_select` semantics in form mode).
- Dead-render gating is core behaviour, covered by tests, not a docs note.

Related: [Spec 001](../specs/spec-001-portable-single-select.md),
[Spec 002](../specs/spec-002-multi-select-chips.md).
