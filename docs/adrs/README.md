# Architecture Decision Records

Code-level decisions and their rationale. ADRs are append-only: once
`accepted`, never edit the decision — write a superseding ADR and update both
status lines and this index. Copy [TEMPLATE.md](./TEMPLATE.md) to start one;
number sequentially.

| ADR | Decision | Status |
|---|---|---|
| [001](./adr-001-two-tier-provider-architecture.md) | Declarative resource config by default; `Flicker.Provider` behaviour as escape hatch | accepted |
| [002](./adr-002-rendering-via-slots-and-theme-map.md) | Rendering via slots + `Flicker.Theme` class-map; no hardcoded CSS framework | accepted |
| [003](./adr-003-fetch-takes-a-list.md) | `Provider.fetch/2` resolves a list of values in one query | accepted |
| [004](./adr-004-authorization-via-actor-and-policies.md) | Authorisation via `actor:`-scoped reads + policies; no bespoke gate | accepted |
| [005](./adr-005-form-field-mode-owns-hidden-inputs.md) | Form-field mode owns hidden inputs + `_unused_` marker; controlled mode separate | accepted |
| [006](./adr-006-core-depends-only-on-provider.md) | Core depends only on `Flicker.Provider`; Ash is the built-in provider; `ash` optional dep | accepted |
| [007](./adr-007-colocated-js-hook.md) | JS ships as a colocated LiveView hook; no npm package | accepted |
| [008](./adr-008-version-floors.md) | Version floors (LiveView ≥ 1.1, Ash ≥ 3.0 optional) + oldest/latest/no-ash CI matrix | accepted |
| [009](./adr-009-messages-module-for-user-facing-text.md) | All user-facing text through one overridable messages module; gettext optional | accepted |
| [010](./adr-010-installer-patches-files-without-igniter-css.md) | Installer wires JS with igniter_js, CSS/config with plain text patches; no igniter_css | accepted |
| [011](./adr-011-facet-editors-are-modal-subcontexts.md) | A rich facet editor is a modal sub-context that commits once, serialising back to token text | proposed |
| [012](./adr-012-parse-reports-invalid-facet-tokens.md) | `Query.parse/2` reports a known facet's uncastable value as invalid instead of degrading it to free text | proposed |
| [013](./adr-013-canonical-tokens-localised-display.md) | Facet tokens are locale-invariant; localisation is a display/input layer via optional `localize` | proposed |
| [014](./adr-014-facet-counts-are-provider-computed-and-actor-scoped.md) | Facet counts are provider-computed, actor-scoped, drill-down-correct, and opt-in | proposed |
