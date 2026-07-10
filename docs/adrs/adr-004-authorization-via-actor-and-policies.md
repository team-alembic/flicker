---
status: accepted
date: 2026-07-10
---

# ADR-004: Authorisation via `actor:`-scoped reads and Ash policies, not a bespoke permission gate

## Context

The ARCC implementation guarded search with a bespoke `read_permission/0`
callback — a boolean pre-check before querying. Ash already has a complete
authorisation story: reads run with an `actor:`, and policies filter what
that actor can see. A parallel permission mechanism would fight the
framework, and worse, a boolean gate is all-or-nothing where policies are
row-level.

## Decision

Flicker performs all reads (search and fetch) as `actor:`-scoped Ash queries
and lets resource policies filter results. The component takes `actor` (and
`tenant`) as first-class attrs and passes them through unmodified. There is
no Flicker-level permission concept. An optional pre-check hook may be
offered for hosts that want to short-circuit rendering entirely (e.g. hide
the control), but it is a convenience, not the security boundary.

Rejected: keeping `read_permission/0` as the gate (parallel authz system,
coarse-grained, drifts from policies).

## Consequences

- Security posture is exactly the host's policies — Flicker can't leak what
  a policy hides, and there is nothing extra to audit.
- Forgetting to pass `actor` is the main foot-gun; docs and the Igniter
  installer must make `actor={@current_user}` the visible default, and the
  component should warn (or raise, configurably) when reads run actorless
  against a resource with policies.

Related: [Spec 001](../specs/spec-001-portable-single-select.md).
