---
status: in-progress # draft | ready | in-progress | shipped
date: 2026-07-23
depends_on: [spec-003, spec-012] # facets; facet pills
---

# Spec 017: Configurable facet value colors

Let a facet declare a colour per value so it renders with a visual cue — e.g.
`status: :active` shows a red dot / red pill. Purely presentational: the colour
travels with the facet definition and drives the pill's (and suggestion's)
styling.

## Scope

- `Flicker.Facet` gains an optional `:value_colors` map (`%{value => color}`),
  alongside the existing `:value_labels`. Configurable in the facet list, e.g.
  `facets={[status: [value_colors: %{active: "green", inactive: "gray"}]]}`.
- Where an enum facet value renders — the committed **pill** (Spec 012) and the
  **value suggestion** rows — a colour indicator shows (a dot, or a tinted pill
  background). The exact treatment is theme-driven.
- Colours are opaque strings the host controls; the library maps a value to its
  colour and exposes it to the markup/theme, it does not hardcode a palette.

## Non-goals

- No colour for non-enum facets (numeric/date/string have open value sets).
- The library doesn't invent colours — unspecified values render with the
  default (uncoloured) treatment.
- Not a full design-token system — a flat value→colour map.

## Design

`value_colors` resolves the same way `value_labels` does (derivable from the
Ash type or set explicitly). Rendering exposes the resolved colour to the pill
markup — e.g. a leading dot `<span style={"background:#{color}"}>` — or, when a
theme opts in, a tinted pill. Keep it a small inline-style/CSS-variable hook so
it works framework-free (ADR-002); a Tailwind/daisy theme can map it to its own
tokens if desired.

## Acceptance criteria

- [ ] A facet with `value_colors` renders each configured value with its colour
      indicator in the pill and the value suggestion row.
- [ ] Values without a configured colour render uncoloured (no crash).
- [ ] The colour is host-supplied; no built-in palette is assumed.
- [ ] Works across presets (framework-free indicator by default).

## Open questions

- Dot vs. tinted-pill-background as the default indicator (or a theme part
  toggling between them).
- Derive default colours from anything (e.g. Ash enum metadata) or explicit-only?
