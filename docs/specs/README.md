# Specs

Feature specifications — each one scoped so it can be implemented from the
spec alone. Copy [TEMPLATE.md](./TEMPLATE.md) to start one; number
sequentially. Statuses: `draft` → `ready` → `in-progress` → `shipped`.
Update the status here **and** in the spec's frontmatter when it changes.

| Spec | Feature | Status |
|---|---|---|
| [001](./spec-001-portable-single-select.md) | Portable single-select: decoupled component, theme, form + controlled modes, hook + installer | shipped |
| [002](./spec-002-multi-select-chips.md) | Multi-select: list value, array inputs, chips, batch `fetch/2` | shipped |
| [003](./spec-003-faceted-search.md) | Faceted search: standalone `Flicker.search` + facets in select/palette; parser, registry, type-derived autocomplete, cursor state machine | shipped |
| [004](./spec-004-provider-contract.md) | `Flicker.Provider` contract: behaviour, structs, built-in Ash provider, `ash` optional | shipped |
| [005](./spec-005-dev-playground.md) | In-repo dev playground: `dev/` Phoenix app, seeded ETS domain, page per capability | shipped |
| [006](./spec-006-keyboard-activation.md) | `activate_with_keyboard="mod+k"`: global shortcut into any Flicker search | shipped |
| [007](./spec-007-screen-reader-support.md) | First-class screen-reader support: announcements, AT test matrix, a11y statement | in-progress |
| [008](./spec-008-command-palette.md) | `Flicker.palette`: ⌘K fullscreen site-search overlay, grouped results, navigate-on-select | shipped |
| [009](./spec-009-cinder-interop.md) | Cinder interop: `Flicker.search` drives a Cinder collection (recipe → adapter → upstream) | shipped |
| [010](./spec-010-windowed-search.md) | Windowed search: opt-in infinite scroll in the listbox, `:offset` provider opt, capped windows | shipped |

Build order is 004 → 001 (005 starts alongside) → 002 → 003; the playground
gains a page as each spec ships (see [DESIGN.md](../DESIGN.md#sequencing)).
