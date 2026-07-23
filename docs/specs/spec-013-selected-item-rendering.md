---
status: draft # draft | ready | in-progress | shipped
date: 2026-07-23
depends_on: [spec-002] # multi-select chips
---

# Spec 013: Configurable selected-item rendering (`:selected` slot + avatar stacking)

`Flicker.select/1` already lets a host customise how *options* render (the
`:option` slot). This adds the symmetric control over how *selected* items
render — a `:selected` slot — plus first-class support for the "stacked
avatars with +N overflow" pattern for multi-select, so a picker of users can
show overlapping profile images instead of text chips.

## Scope

- **`:selected` slot** on `Flicker.select/1`. Given a result, it renders that
  selected item's visual. Without it, the current default renders (a text
  chip in multi-select; the resolved label in the input for single-select).
  Receives the same `result` (`%Flicker.Result{}`, incl. `meta.record`) the
  `:option` slot gets, plus a `remove` helper/event target so custom markup
  can still offer removal.
- **Stacking layout for multi-select**: a `max_visible` attr (integer). When
  the selection exceeds it, the first `max_visible` render via `:selected`
  and the remainder collapse into a themed "+N" overflow token. Off by
  default (all chips shown).
- **New theme parts**: `:selected_stack` (the overlapping-avatars container,
  e.g. negative margins) and `:selected_overflow` (the "+N" token). Covered
  by all presets; `ThemeTest` enforces coverage.
- **Example**: a new playground page (or a section) — a user picker where
  each option shows an avatar + name, and the selection renders as a stack of
  three overlapping avatars then "+2". Avatars come from a free hosted API
  (e.g. DiceBear `https://api.dicebear.com/9.x/…/svg?seed=…`, or pravatar) —
  seed a small user resource so the images are stable per record.

## Non-goals

- No image proxying/caching in the library — the host supplies image URLs (in
  `meta.record`); the demo just points at a public avatar API.
- No drag-reorder of the stack.
- Not changing the option-rendering slot (`:option`) — this is its mirror.

## Design

```heex
<Flicker.select multiple resource={User} search={[:name]} max_visible={3}>
  <:option :let={r}>
    <img src={r.meta.record.avatar_url} class="h-6 w-6 rounded-full" /> {r.label}
  </:option>
  <:selected :let={r}>
    <img src={r.meta.record.avatar_url} title={r.label} class="h-8 w-8 rounded-full ring-2 ring-white" />
  </:selected>
</Flicker.select>
```

The component keeps owning selection state, `max_selections`, form/controlled
modes; the slot only owns pixels. The overflow token renders after the first
`max_visible` selected items and carries an accessible label ("+2 more"). When
`:selected` is present it replaces the chip's inner markup but the library
still provides the remove affordance (either the slot calls a passed
`remove` event, or a default remove control wraps the slot — decide during
implementation, leaning toward the slot opting in).

## Acceptance criteria

- [ ] With a `:selected` slot, each selected item renders the slot's markup
      instead of the default chip.
- [ ] Without it, behaviour is byte-identical to today (Spec 002 chips).
- [ ] `max_visible={3}` with 5 selected shows 3 rendered items + a "+2" token
      with an accessible "2 more" label.
- [ ] Removal still works from custom selected markup.
- [ ] The avatar example page renders real images and stacks them.
- [ ] `ThemeTest` covers the new parts across all presets.

## Open questions

- Remove affordance in custom selected markup: a passed `remove` target vs. a
  library-wrapped remove button vs. click-to-remove. Resolve before `ready`.
- Does single-select want `:selected` too (render the chosen record richly in
  the closed input), or is this multi-only for v1?
