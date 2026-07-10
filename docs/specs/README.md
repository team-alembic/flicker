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

Build order is 001 → 002 → 003 (see [DESIGN.md](../DESIGN.md#sequencing)).
