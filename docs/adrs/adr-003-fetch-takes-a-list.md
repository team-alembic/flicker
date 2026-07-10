---
status: accepted
date: 2026-07-10
---

# ADR-003: `Provider.fetch/2` resolves a list of values, not a single value

## Context

The original `Search.Source.fetch/2` took one value: given a stored id,
resolve the record to display its label. Multi-select breaks this — an edit
form opening with three `worker_ids` set must label all three, and calling a
singular fetch per value means N round-trips (N queries, N policy checks) on
every mount.

## Decision

```elixir
@callback fetch(values :: [term()], opts :: keyword()) ::
            {:ok, [Flicker.Result.t()]} | {:error, term()}
```

`fetch/2` takes a **list** and returns results for all resolvable values in
one query. Single-select passes a one-element list. Values that don't resolve
(deleted or policy-filtered records) are simply absent from the result list —
not an error.

Rejected: singular `fetch` called per value (N+1), a separate `fetch_many`
alongside singular `fetch` (two callbacks for one job; providers would
implement one in terms of the other anyway).

## Consequences

- One callback shape serves single- and multi-select; Tier 1's derived
  provider implements it as a single `value in ^values` read.
- Callers must handle partial results (fewer results than values) — this is
  the natural behaviour when a selected record has since been deleted or
  hidden by policy.

Related: [ADR-001](./adr-001-two-tier-provider-architecture.md),
[Spec 002](../specs/spec-002-multi-select-chips.md).
