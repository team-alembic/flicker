---
status: accepted
date: 2026-07-10
---

# ADR-001: Two-tier architecture — declarative resource config by default, provider behaviour as escape hatch

## Context

The ARCC implementation Flicker is extracted from required a `Search.Source`
module per record type. That is the right shape for federated/global search,
but it is too heavy for the common case: "search this one resource on these
fields". Requiring a module per picker adds boilerplate and a naming decision
before any value is delivered, and it is exactly the options-plumbing overhead
that Ash-native libraries (Cinder) avoid.

## Decision

Flicker has two tiers:

**Tier 1 — declarative (the 90% case).** No module. The component takes the
resource and field config inline, and Flicker derives an anonymous provider
from them:

```heex
<Flicker.select
  field={f[:client_id]}
  resource={MyApp.Client}
  actor={@current_user}
  search={[:first_name, :last_name, :uci_number]}
  option_label={:full_name}
  read_action={:search}
  limit={20}
/>
```

**Tier 2 — `Flicker.Provider` behaviour.** For federated multi-resource
search and non-standard sources:

```elixir
@callback search(query :: Flicker.Query.t(), opts :: keyword()) ::
            {:ok, [Flicker.Result.t()]} | {:error, term()}
@callback fetch(values :: [term()], opts :: keyword()) ::
            {:ok, [Flicker.Result.t()]} | {:error, term()}
@callback facets() :: [Flicker.Facet.t()]                          # optional
@callback render_option(Flicker.Result.t(), assigns) :: rendered   # optional
```

Rejected: behaviour-only (the status quo — too heavy, see Context) and
declarative-only (kills federated/global search, which is a proven need).

## Consequences

- Tier 1 must be genuinely complete for single-resource use; if common cases
  keep forcing users into Tier 2, the tiering has failed.
- The internal query path must be provider-shaped: Tier 1 compiles down to an
  anonymous provider, so there is exactly one execution path.
- The `facets/0` and `render_option/2` callbacks are optional so trivial
  providers stay trivial.

Related: [ADR-003](./adr-003-fetch-takes-a-list.md) (the `fetch/2` shape),
[Spec 001](../specs/spec-001-portable-single-select.md).
