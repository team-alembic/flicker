---
status: ready
date: 2026-07-10
depends_on: [adr-001, adr-003, adr-004, adr-006]
---

# Spec 004: The `Flicker.Provider` contract

The data-source contract everything else compiles down to: a documented pure
Elixir behaviour, the built-in Ash resource provider that Tier 1 config
produces, and a reference in-memory provider used in tests. Pure Elixir end
to end — no LiveView, no browser — so it is built and tested first, before
any component work ([Spec 001](./spec-001-portable-single-select.md) builds
on it).

## Scope

- **`Flicker.Provider` behaviour** ([ADR-001](../adrs/adr-001-two-tier-provider-architecture.md)):

  ```elixir
  @callback search(query :: Flicker.Query.t(), opts :: keyword()) ::
              {:ok, [Flicker.Result.t()]} | {:error, term()}
  @callback fetch(values :: [term()], opts :: keyword()) ::
              {:ok, [Flicker.Result.t()]} | {:error, term()}   # list-in, one query — ADR-003
  @callback facets() :: [Flicker.Facet.t()]                     # optional
  @callback render_option(Flicker.Result.t(), assigns) :: rendered  # optional
  ```

  `opts` carries `actor`, `tenant`, `limit`, and provider-specific options.
  Optional callbacks via `@optional_callbacks`; core detects them with
  `function_exported?/3`.

- **Structs**: `%Flicker.Result{value, label, sublabel, meta}` and
  `%Flicker.Query{text, facets}` (facets empty until
  [Spec 003](./spec-003-faceted-search.md); the shape exists from day one so
  the contract doesn't churn).

- **`Flicker.Providers.AshResource`** — the built-in provider Tier 1 config
  compiles to: takes resource, `search` fields, `option_label`/`option_sublabel`,
  `read_action`, `limit`, `sort`, base filter; runs `actor:`/`tenant:`-scoped
  reads ([ADR-004](../adrs/adr-004-authorization-via-actor-and-policies.md));
  ilike over the search fields; `fetch/2` as a single `value in ^values` read.

- **Reference pure-Elixir provider** — a small in-memory list provider
  (`Flicker.Providers.Static` or test-support equivalent) proving the
  contract stands alone and serving as the component test double.

- **Optional-dependency boundary** ([ADR-006](../adrs/adr-006-core-depends-only-on-provider.md)):
  `ash` marked `optional: true`; `Flicker.Providers.AshResource` compiles
  only when Ash is present (`Code.ensure_loaded?/1` guard); a CI leg
  compiles and runs core tests without `ash`.

- **Docs**: behaviour documented well enough that "write your own provider"
  needs no source-diving; a short guide with the in-memory provider as the
  worked example.

## Non-goals

- The component itself — rendering, keyboard, forms ([Spec 001](./spec-001-portable-single-select.md)).
- Facet derivation and `Flicker.Facet` semantics beyond a placeholder struct
  ([Spec 003](./spec-003-faceted-search.md)).
- Search strategies beyond ilike (trigram/full-text are internal upgrades to
  the Ash provider later).
- Marketing the non-Ash path: it's supported and documented, not a pillar
  (see ADR-006).

## Design

Provider identity is `module` or `{module, opts}`; Tier 1 attrs compile to
`{Flicker.Providers.AshResource, compiled_opts}` at mount. Core invokes
providers through a single internal boundary (`Flicker.Provider.run_search/3`
etc.) so cross-cutting behaviour (timing, error normalisation, stale-result
tagging hooks for Spec 001) lives in one place.

Error philosophy: providers return `{:error, term}`; the core renders a
themed error state and never raises on provider failure. Partial `fetch/2`
results are normal, not errors ([ADR-003](../adrs/adr-003-fetch-takes-a-list.md)).

## Acceptance criteria

- The in-memory provider implements the behaviour with only `phoenix_live_view`
  (not `ash`) loaded; the full core test suite passes in a build where `ash`
  is absent from the deps.
- `Flicker.Providers.AshResource.search/2` respects actor/policies, tenant,
  limit, sort, and base filter; `fetch/2` resolves N values in exactly one
  query and silently omits unresolvable values.
- Tier 1 component config and a hand-written `{AshResource, opts}` provider
  produce identical results for identical input — proving one execution path.
- A third-party can implement a provider (e.g. wrapping an HTTP API) from
  the docs alone: behaviour `@doc`s + guide, no source-diving.
- Both structs are stable public API: documented, with typespecs, covered by
  Dialyzer.

## Open questions

- Should `search/2` support an async/streaming shape for slow federated
  providers, or is "return a list, core handles cancellation" enough for
  v1? (Assume the latter; revisit if global search needs it.)
