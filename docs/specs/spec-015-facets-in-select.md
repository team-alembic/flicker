---
status: draft # draft | ready | in-progress | shipped
date: 2026-07-23
depends_on: [spec-003, spec-012] # faceted parser; facet pills
---

# Spec 015: Inline facets in `Flicker.select`

`Flicker.search/1` renders committed facets as removable pills (Spec 012) and
`Flicker.select/1` already *parses* facets for filtering its record search
(Spec 003's "facets in select"), but the select shows facet tokens as raw text
in the input rather than as pills. This brings the tokenised pill UX into the
select so a searchable single/multi select given `facets={…}` filters *and*
displays them the same way the standalone search does.

## Scope

- When `Flicker.select/1` is given `facets`, completed facet tokens render as
  removable pills inside the field (reusing Spec 012's `:facet_pill*` parts and
  the `:multi_field` box), with the remaining free text driving the record
  search as today.
- Works for both single- and multi-select. In multi-select the facet pills and
  the selected-value chips coexist in the field (facets scope the search;
  chips are the chosen records) — the spec must define their visual ordering
  and that they are distinct (a facet pill filters, a chip is a selection).
- Removing a facet pill re-runs the record search without that facet; the
  emitted selection/`on_select` payload is unaffected (facets only scope what's
  searchable).

## Non-goals

- No new parsing/filtering semantics — reuse `Flicker.Query`/`FacetSuggest`
  already wired into the select.
- Not changing single-select's resolved-selection-in-the-input behaviour when
  no facets are configured.

## Design

Lift the committed-facet extraction (`absorb_committed`, `:committed`,
`remove_facet`, the pill rendering, the value hints) out of
`Flicker.Components.Search` into shared code both components use, rather than
duplicating it. The select already has `facet_context`, `run_faceted_search`,
and the cursor machine; the addition is the committed/pill layer on top, gated
on `facets != []`. The trickiest part is the multi-select field holding *both*
facet pills and selection chips — likely: facet pills first (they scope), then
chips, then the input, all inside `:multi_field`.

## Acceptance criteria

- [ ] A single-select with `facets` shows `status:active` as a removable pill,
      not raw text, and filters the record search by it.
- [ ] A multi-select with `facets` shows facet pills and selection chips as
      visually distinct things in one field.
- [ ] Removing a facet pill re-runs the search; removing a chip changes the
      selection — they don't interfere.
- [ ] No behaviour change when `facets` is empty.

## Open questions

- Shared-code extraction: a common module/behaviour vs. a shared component —
  decide to avoid Search/Select drift.
- Multi-select ordering/affordance of pills vs. chips in one field; do they
  need separate rows?
