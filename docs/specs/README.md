# Specs

Feature specifications — each one scoped so it can be implemented from the
spec alone. Copy [TEMPLATE.md](./TEMPLATE.md) to start one; number
sequentially. Statuses: `draft` → `ready` → `in-progress` → `shipped`.
Update the status here **and** in the spec's frontmatter when it changes.

| Spec | Feature | Status |
|---|---|---|
| [001](./spec-001-portable-single-select.md) | Portable single-select: decoupled component, theme, form + controlled modes, hook + installer | ready |
| [002](./spec-002-multi-select-chips.md) | Multi-select: list value, array inputs, chips, batch `fetch/2` | ready |
| [003](./spec-003-faceted-search.md) | Faceted search: parser, facet registry, type-derived autocomplete, cursor state machine | draft |
| [004](./spec-004-provider-contract.md) | `Flicker.Provider` contract: behaviour, structs, built-in Ash provider, `ash` optional | ready |
| [005](./spec-005-dev-playground.md) | In-repo dev playground: `dev/` Phoenix app, seeded ETS domain, page per capability | ready |
| [006](./spec-006-keyboard-activation.md) | `activate_with_keyboard="mod+k"`: global shortcut into any Flicker search | draft |
| [007](./spec-007-screen-reader-support.md) | First-class screen-reader support: announcements, AT test matrix, a11y statement | draft |

Build order is 004 → 001 (005 starts alongside) → 002 → 003; the playground
gains a page as each spec ships (see [DESIGN.md](../DESIGN.md#sequencing)).
