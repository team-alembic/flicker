---
status: accepted
date: 2026-07-10
---

# ADR-007: JS ships as a LiveView colocated hook, not an npm package

## Context

Flicker needs client-side JS (keyboard navigation, activation shortcuts,
focus management) delivered to every host app. The two candidate channels:
an npm package the host installs and imports, or LiveView 1.1+ colocated
hooks, where the JS lives next to the component source in the Hex package
and is extracted at compile time for the host bundler to import via
`phoenix-colocated/flicker`.

An npm package means a second release pipeline, version-skew between the
Hex and npm artefacts, and a foot in an ecosystem the library otherwise
doesn't need. The project's bias is to stay as close to Elixir/LiveView as
possible.

## Decision

All Flicker JS ships as colocated hooks inside the Hex package. There is no
npm package and no npm dependency — any client-side behaviour we need is
hand-rolled in the hook. The Igniter installer wires the
`phoenix-colocated/flicker` import into the host's bundle; docs cover the
manual step for hosts on non-esbuild bundlers.

Rejected: npm package (second release pipeline, skew, ecosystem weight);
installer-copies-a-JS-file (the copy doesn't track library upgrades and
drifts silently).

## Consequences

- The LiveView floor becomes `~> 1.1` (colocated hooks) — recorded in
  [ADR-008](./adr-008-version-floors.md).
- One artefact, one version: the JS can never be newer or older than the
  Elixir code using it.
- The hook must stay small and dependency-free; if a feature seems to need
  an npm dep, the feature gets rethought.
- Non-esbuild hosts (custom Vite/webpack setups) need a documented import
  path; the installer targets the standard Phoenix esbuild layout.

Related: [Spec 001](../specs/spec-001-portable-single-select.md),
[Spec 006](../specs/spec-006-keyboard-activation.md).
