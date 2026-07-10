---
status: shipped
date: 2026-07-10
depends_on: [spec-001, adr-003, adr-005]
---

# Spec 002: Multi-select with chips

Extend the single-select into pick-many: the value becomes a list, selections
render as removable chips, and label resolution stays one query regardless of
how many values are selected.

## Scope

- **List value.** `multiple` mode where the selection is a list of values;
  form-field mode emits `name[]` array hidden inputs
  ([ADR-005](../adrs/adr-005-form-field-mode-owns-hidden-inputs.md));
  controlled mode's `on_select` carries the full selection list.
- **Chips UX.** Each selected value renders as a chip (label + ✕ remove);
  a "clear all" control; backspace in an empty search input removes the last
  chip. Chip and chip-remove are themed parts
  ([ADR-002](../adrs/adr-002-rendering-via-slots-and-theme-map.md)).
- **Batch label resolution.** `fetch/2` resolves all selected values in one
  call ([ADR-003](../adrs/adr-003-fetch-takes-a-list.md)).
- **Result filtering.** Options already selected are excluded from the
  dropdown; `max_selections` caps the list and disables further picking at
  the cap.

## Non-goals

- Facet-driven filtering ([Spec 003](./spec-003-faceted-search.md)).
- Drag-reordering of chips, grouping, or "select all matching".

## Design

Same component, `multiple` switches the value model — `<Flicker.select
multiple />` **is** the multi-select surface; there is no `Flicker.multi_select`
(see the component-surface table in [DESIGN.md](../DESIGN.md#component-surface)).
Single-select is the one-element degenerate case internally where practical. State: `selected :: [Flicker.Result.t()]`, kept
as Results (not bare values) so chips render without refetching; `fetch/2`
runs once on mount/update when values arrive without labels (e.g. edit form
opening with `worker_ids` already set).

Accessibility: chips are a labelled list; each remove control gets a
screen-reader label naming the chip ("Remove Casey Nguyen"); selection
changes are announced.

## Acceptance criteria

- An edit form opening with three ids set shows three labelled chips after
  exactly one `fetch/2` call (one query).
- Submitting the form yields `%{"worker_ids" => [id1, id2, id3]}` — array
  params with no host-side transformation.
- Values deleted/policy-hidden since selection are dropped gracefully
  (partial `fetch` results), not crashed on.
- A selected option no longer appears in search results; removing its chip
  makes it searchable again.
- At `max_selections`, further selection is prevented and communicated;
  removing a chip re-enables it.
- Backspace in an empty search input removes the last chip; ✕ removes any
  chip; "clear all" empties the selection — all reflected in params/`on_select`.
- The `_unused_` recovery behaviour from Spec 001 holds for array inputs
  across a LiveSocket reconnect.

## Open questions

- None blocking. Chip overflow presentation (many selections in a narrow
  control) can be a theme/preset concern initially.
