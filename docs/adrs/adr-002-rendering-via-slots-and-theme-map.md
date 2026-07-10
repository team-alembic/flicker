---
status: accepted
date: 2026-07-10
---

# ADR-002: Rendering via slots plus a theme class-map, no hardcoded CSS framework

## Context

The extracted component hardcodes daisyUI classes and assumes heroicons and
the origin app's UI helpers. A published library cannot assume any CSS
framework, and hosts need to restyle every visual part without forking the
component. Cinder solved the same problem with a theme system; Flicker should
feel familiar to Cinder users.

## Decision

Two mechanisms, split by concern:

- **Structure/content overrides via slots.** Default option rendering uses
  `Flicker.Result`'s `label`/`sublabel`; hosts override with an `:option`
  slot (icons, badges, avatars) reading from `meta`.
- **Styling via `Flicker.Theme`** — a class-per-part map (control, listbox,
  option, chip, chip-remove, search-input, hint, empty-state) with swappable
  presets: vanilla / Tailwind / daisyUI. Configurable globally
  (`config :flicker, default_theme:`) and per-component.

Consequently `Flicker.Result` shrinks to `%Flicker.Result{value, label,
sublabel, meta}` — app-specific fields like `type`/`icon`/`bg_class` move
into `meta` and are the slot's business.

Rejected: hardcoded framework classes (not publishable), CSS-custom-property
theming only (can't restructure markup), render-callback-only (loses HEEx
ergonomics for the common restyle case).

## Consequences

- Every visually distinct part must have a named theme key from day one;
  adding keys later is easy, renaming them is a breaking change.
- Core never emits framework-specific classes outside theme presets.
- Presets need visual regression coverage or they will rot silently.

Related: [Spec 001](../specs/spec-001-portable-single-select.md).
