---
status: accepted
date: 2026-07-10
---

# ADR-006: Core depends only on `Flicker.Provider`; Ash integration is the built-in provider; `ash` is an optional dependency

## Context

[ADR-001](./adr-001-two-tier-provider-architecture.md) decided the two-tier
*config* shape (inline resource config vs a provider module) but left the
dependency structure implicit: does the component core call Ash directly for
the Tier 1 path, or does everything go through the `Flicker.Provider`
behaviour? The distinction matters for three audiences:

- **Non-Ash hosts.** A plain-Phoenix app with a static option list, an
  external HTTP API, or Ecto-without-Ash gets a documented pure-Elixir
  contract to implement instead of being told "use Ash or use LiveSelect".
- **Internals.** One execution path is dramatically easier to reason about
  and test than two ("declarative" and "provider") that must be kept in
  behavioural lockstep.
- **Testing.** The component core can be exercised with a trivial in-memory
  provider — no Ash resources, no data layer — keeping component tests fast
  and focused.

## Decision

The component core (rendering, state, keyboard handling, form integration,
debounce/cancellation) depends **only** on the `Flicker.Provider` behaviour.
Ash integration lives in `Flicker.Providers.AshResource`, the built-in
provider that Tier 1 config compiles to. Consequently:

- `ash` (and `ash_phoenix`) are `optional: true` dependencies. Only
  `phoenix_live_view` is required.
- Nothing under the core namespace may call `Ash.*`; Ash-specific
  capabilities (declarative config, type-derived facets) are features of the
  built-in provider, not of the core.
- The pure-Elixir contract is documented and supported — but it is an escape
  hatch, not a marketed pillar. Flicker's pitch stays Ash-*first* (see the
  differentiation test in [DESIGN.md](../DESIGN.md)); polish beyond "works
  and is documented" waits until the Ash story is proven in ARCC.

Rejected: core calling Ash directly for Tier 1 (two execution paths to keep
in lockstep; hard `ash` dep for hosts that don't need it), and a separate
`flicker_ash` package (ecosystem fragmentation and version-matrix pain that
optional deps solve for free).

## Consequences

- CI needs a compile/test matrix leg **without** `ash` present, or the
  optional boundary will rot silently.
- The behaviour's contract must be complete enough that the built-in Ash
  provider has no private side-channel into the core — if the Ash provider
  needs a capability, the contract grows for everyone.
- Facet derivation ([Spec 003](../specs/spec-003-faceted-search.md)) is
  specified as an `AshResource` provider capability, with `facets/0` as the
  manual path for pure providers.

Related: [Spec 004](../specs/spec-004-provider-contract.md).
