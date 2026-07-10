---
status: accepted
date: 2026-07-10
---

# ADR-008: Version floors and the CI support matrix

## Context

Nothing recorded which Elixir/OTP/Phoenix/Ash versions Flicker supports,
and [ADR-006](./adr-006-core-depends-only-on-provider.md)'s optional-`ash`
boundary only holds if CI actually compiles without Ash. Floors chosen
implicitly by whatever the dev machine runs are floors chosen badly.

## Decision

Initial floors (mix.exs is the living source of truth; this ADR records the
starting point and the policy):

| Dependency | Floor | Why |
|---|---|---|
| Elixir | `~> 1.17` | matches existing mix.exs |
| OTP | 26+ | oldest OTP supported by Elixir 1.17 line |
| `phoenix_live_view` | `~> 1.1` | colocated hooks ([ADR-007](./adr-007-colocated-js-hook.md)) |
| `ash` | `~> 3.0`, **optional** | [ADR-006](./adr-006-core-depends-only-on-provider.md) |
| `ash_phoenix` | `~> 2.0`, **optional** | form adapter only ([ADR-005](./adr-005-form-field-mode-owns-hidden-inputs.md)) |

CI matrix (in `.github/workflows/elixir.yml`):

- **oldest leg** — floor Elixir/OTP with lowest supported dep versions
  (`mix deps.get` with floors pinned), full suite.
- **latest leg** — latest stable Elixir/OTP and deps, full suite. This is
  the leg that runs the full quality gate (`mix check`).
- **no-ash leg** — latest stable, with `ash`/`ash_phoenix` excluded;
  compiles with `--warnings-as-errors` and runs the core test suite. This
  leg exists from the first Spec 004 commit or the optional boundary rots.

Policy: raising any floor is at least a minor version bump with a
CHANGELOG entry (pre-1.0: a `0.x` minor). New optional integrations follow
the same optional-dep + CI-leg pattern as `ash`.

## Consequences

- The no-ash leg forces the `Code.ensure_loaded?`-guarded compilation of
  `Flicker.Providers.AshResource` to be correct continuously, not
  aspirationally.
- Supporting LiveView 1.0 hosts is explicitly out; hosts that can't take
  1.1 can't take Flicker. Accepted cost of ADR-007.
- The oldest leg pins floor versions, so an accidental use of a
  newer-than-floor API fails in CI rather than in a consumer's app.
