---
status: shipped # draft | ready | in-progress | shipped
date: 2026-07-23
depends_on: [spec-003, adr-002] # faceted search parser/registry; class-per-part theme
---

# Spec 012: Facet pills (tokenised faceted input)

Committed facets in `Flicker.search` (and, by extension, `Flicker.palette`)
render as removable, styled **pills** instead of living as raw
`key:value` text in the input. Once a facet parses cleanly and the user
finishes it, it lifts out of the text buffer into a pill row; the input
keeps only the free-text remainder and any in-progress token. This is the
tokenised-input pattern faceted search bars use (Linear, GitHub, Jira): the
committed filters are visible, labelled, and dismissable, and the text field
is just for what you're typing next.

## Scope

User-visible behaviour:

- A committed facet renders as a pill showing the **value's display label**
  (e.g. `Established`, not `established`) as the primary text, with the
  **facet's field label** small in the pill's top-right corner, no colon,
  on a coloured background.
- A pill has a remove control (`×`); removing it re-emits the query without
  that facet and returns the removed token's slot to the input if it was the
  in-progress one.
- `Backspace` in an empty text buffer removes the last pill (mirrors Spec
  002's chip behaviour in multi-select).
- The text input shows only the free-text remainder plus any token still
  being typed — committed `key:value` tokens no longer clutter it.
- Every existing `Flicker.search` behaviour (facet-key/value autocomplete,
  the cursor state machine, `on_change` emitting `{query, filter}`) keeps
  working unchanged from the caller's point of view.

Public API / surface:

- No new component attrs. Pills are on by default whenever `facets` are
  configured (they *are* the committed-facet rendering — there is no
  no-pills mode to preserve; the raw-text rendering was never a documented
  contract).
- New theme parts (ADR-002 class-per-part): `:facet_pill` (container),
  `:facet_pill_field` (the corner field label), `:facet_pill_value`
  (primary value text), `:facet_pill_remove` (the `×` button), and
  `:facet_pill_list` (the wrapper row). Every preset
  (`vanilla`/`tailwind`/`daisy_ui`) covers them; `Flicker.ThemeTest` enforces
  coverage automatically off the struct keys.
- `Flicker.Facet` gains a way to resolve a value's display label
  (`value_label/2` or similar) — enum facets defer to the Ash type's
  `label/1` when present, otherwise humanise the atom; string/number/date
  facets render the cast value.

## Non-goals

- No change to `Flicker.Query` parsing, `:input` round-trip, or `to_filter/2`
  — pills are a *rendering + edit* layer over the same parsed query. `:input`
  stays the canonical, re-parseable source of truth (Spec 003).
- No pills in the plain `Flicker.select/1` record picker — it has no facets.
  (If a select is later given `facets`, this rendering applies there too, but
  that's not a target of this spec.)
- No drag-to-reorder, grouping, or editing a pill's value in place —
  remove-and-retype only.
- No multi-value "OR" pill grouping UI; repeated same-key facets render as
  separate pills (they already OR in `to_filter/2`).

## Design

The canonical state stays the input string (Spec 003): `parse/2` turns it
into `%Flicker.Query{text, facets, input}`. Pills are derived from
`query.facets`; the visible input value is derived from `query.text` plus the
single trailing in-progress token (the one under the cursor that hasn't
committed yet).

**Commit boundary.** A facet token is *committed* once it is both (a) a clean
parse (`{:facet, ...}`) and (b) terminated — followed by whitespace, or the
user picked it from the value autocomplete (`select_suggestion` already
appends a trailing space). The token under the cursor with no trailing
whitespace is *in-progress* and stays in the text buffer so the cursor state
machine (`Flicker.CursorContext`) can keep classifying it for autocomplete.
This keeps the Spec 003 machine intact: it still sees a live token; it just
never sees the already-committed ones.

**Rendering.** A `:facet_pill_list` row sits before the input. For each
committed facet `{key, op, value}` resolve the `Flicker.Facet` from the
registry to get the field label and the value's display label:

```heex
<span class={@theme.facet_pill}>
  <span class={@theme.facet_pill_field}>{facet_field_label(facet)}</span>
  <span class={@theme.facet_pill_value}>{facet_value_label(facet, value, op)}</span>
  <button class={@theme.facet_pill_remove} phx-click="remove_facet"
          phx-value-index={index} aria-label={remove_message}>×</button>
</span>
```

Non-`:eq` operators surface in the value label (`≥ 1980-01-01`) so a
`monthly_listeners > 100000` pill isn't ambiguous.

**Removal.** `remove_facet` with the pill's index rebuilds the input string
with that token dropped (splice on the token boundaries `parse/2` already
knows), re-runs `parse/2`, re-emits `on_change`, and pushes the rebuilt value
to the input via the existing `focusElementById` value channel.

**Tailwind pill look** (matches the request — value primary, field small
top-right, coloured, no colon):

```
facet_pill:       "relative inline-flex flex-col rounded-md bg-indigo-50 py-1 pl-2 pr-6 text-indigo-900"
facet_pill_field: "self-end text-[10px] uppercase tracking-wide text-indigo-400"
facet_pill_value: "text-sm font-medium"
facet_pill_remove:"absolute right-1 top-1 text-indigo-400 hover:text-indigo-700"
facet_pill_list:  "mb-2 flex flex-wrap gap-1.5"
```

## Acceptance criteria

- [ ] Typing `status:active ` (trailing space) removes `status:active` from
      the input value and renders one pill: value `Active`, field `Status`,
      no colon.
- [ ] An enum value renders its display label, not the lowercased atom
      (`Established`, `Legendary`).
- [ ] A non-`:eq` facet pill shows its operator (`≥ 1980-01-01`).
- [ ] Clicking a pill's `×` re-emits `on_change` with a `filter` no longer
      containing that facet, and the input value reflects the removal.
- [ ] `Backspace` in an empty text buffer removes the last pill and emits the
      updated query.
- [ ] The in-progress token (no trailing space) stays in the input and still
      drives value autocomplete (Spec 003 cursor machine unchanged).
- [ ] `on_change`'s `{query, filter}` payload is byte-identical to the
      pre-pills output for the same committed set (pills are presentation).
- [ ] `Flicker.ThemeTest` passes with the new parts covered by all presets.
- [ ] The `/faceted-search` playground page shows the pills against the mixed
      seed data (tier/status/date), proving filtering.

## Open questions

- **Focus/keyboard order of pills vs. suggestions.** Pills are focusable
  buttons before the input; arrow-key nav over the *suggestion* listbox must
  not be intercepted by pill focus. Likely: pills are Tab-reachable but the
  suggestion arrow-nav stays bound to the input. Confirm against Spec 007's
  keyboard map before marking `ready`.
- **Palette footer interaction.** `Flicker.palette` reuses the nested search;
  pills inside a fullscreen palette want vertical spacing tuning, not a
  different mechanism. Cosmetic, non-blocking.
