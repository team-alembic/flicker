---
status: in-progress # draft | ready | in-progress | shipped
date: 2026-07-23
depends_on: [spec-005, adr-002] # dev playground; class-per-part theme
---

# Spec 016: Per-theme showcase pages with a theme picker and copyable theme code

Today `/themes` is one page showing the three presets side by side. Replace it
with a proper showcase: one page per preset (vanilla / Tailwind / daisyUI),
each rendering the *whole* page in that theme, a theme picker in the top-right
to switch between them, and — for each — the copyable code you'd need to adopt
that theme (CSS for vanilla, utility classes for Tailwind, component classes
for daisyUI).

## Scope

- Three routes/pages: `/themes/vanilla`, `/themes/tailwind`, `/themes/daisy`
  (or one page + a `theme` param). Each renders the same set of Flicker
  examples themed entirely with that preset.
- A **theme picker** control fixed top-right of the showcase, switching the
  active theme (updates the page's theme + the copyable code, via
  `live_navigate`/param).
- A **copyable theme snippet** per theme (reusing Spec 014's `code_example`):
  - vanilla → the `flicker-*` CSS a host writes (a starter stylesheet), ideally
    editable inline so tweaks preview live (stretch goal).
  - Tailwind → `Flicker.Theme.tailwind()` (or the class map) to drop in.
  - daisyUI → `Flicker.Theme.daisy_ui()`.
- Nav updated (`Dev.UI` nav groups) to point at the themed pages.

## Non-goals

- No new theme presets — just showcasing the three that ship.
- Inline-editable live CSS is a stretch goal; the base deliverable is
  copyable, correct snippets.
- No change to `Flicker.Theme` itself (this is playground/docs).

## Design

Each page assigns the chosen `%Flicker.Theme{}` and passes it to every example
via `theme={@theme}`. The picker is a small segmented control (top-right of the
`Dev.UI` page header) linking to each theme page. The vanilla page additionally
renders a `<style>` block of starter `flicker-*` rules so the framework-free
preset actually looks like something, and shows that same CSS in a
`code_example`. Inline-edit (stretch) = a `<textarea>` bound to the `<style>`
contents via a tiny colocated hook.

## Acceptance criteria

- [ ] Three themed pages, each rendering the examples fully in its preset.
- [ ] A top-right theme picker switches theme (and the shown snippet).
- [ ] Each page shows the copyable adoption code for its theme.
- [ ] Vanilla page ships starter CSS so it's not unstyled.
- [ ] Nav points at the new pages; old `/themes` redirects or is replaced.

## Open questions

- One page + `?theme=` param vs. three routes — pick for clean nav + `live_nav`.
- Inline-editable vanilla CSS: worth the colocated-hook complexity in v1?
