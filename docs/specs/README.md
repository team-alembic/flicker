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
| [007](./spec-007-screen-reader-support.md) | First-class screen-reader support: announcements, a11y statement (manual AT matrix → [release checklist](../RELEASE_CHECKLIST.md)) | shipped |
| [008](./spec-008-command-palette.md) | `Flicker.palette`: ⌘K fullscreen site-search overlay, grouped results, navigate-on-select | shipped |
| [009](./spec-009-cinder-interop.md) | Cinder interop: `Flicker.search` drives a Cinder collection (recipe → adapter → upstream) | shipped |
| [010](./spec-010-windowed-search.md) | Windowed search: opt-in infinite scroll in the listbox, `:offset` provider opt, capped windows | shipped |
| [011](./spec-011-router-navigation-provider.md) | Router navigation provider: palette navigates the host's Phoenix routes with one config flag | shipped |
| [012](./spec-012-facet-pills.md) | Facet pills: committed facets render as removable styled pills, tokenised faceted input | shipped |
| [013](./spec-013-selected-item-rendering.md) | Configurable selected-item rendering: `:selected` slot + avatar stacking with +N overflow | shipped |
| [014](./spec-014-copyable-example-code.md) | Copyable example code blocks in the playground, component-library style | shipped |
| [015](./spec-015-facets-in-select.md) | Inline facets in `Flicker.select`: committed facet pills + filtering in the select, not just search | shipped |
| [016](./spec-016-themed-showcase.md) | Per-theme showcase pages + theme picker + copyable per-theme adoption code | shipped |
| [017](./spec-017-facet-value-colors.md) | Configurable facet value colours (e.g. a red dot/pill for `status:active`) | shipped |
| [018](./spec-018-rich-facet-types.md) | Rich facet types: range/list grammar, date presets, type derivation, value validation, CLDR display | shipped |
| [019](./spec-019-facet-editors.md) | Facet editors: pop-out contract, calendar + presets rail, numeric dial, switch, set editor | shipped |
| [020](./spec-020-query-dispatch-policy.md) | Query dispatch policy: debounce/immediate/enter, request supersession, stale-while-revalidate | shipped |
| [021](./spec-021-facet-value-counts.md) | Facet value counts: optional provider callback, actor-scoped drill-down counts beside each value | shipped |
| [022](./spec-022-recently-used-values.md) | Recently-used facet values: host-provided storage, frecency ranking, `Recent` group | shipped |
| [023](./spec-023-inline-value-correction.md) | Inline value correction + invalid-value policy (`:drop`/`:require`), swap/clamp fixes | shipped |

Build order is 004 → 001 (005 starts alongside) → 002 → 003; the playground
gains a page as each spec ships (see [DESIGN.md](../DESIGN.md#sequencing)).
