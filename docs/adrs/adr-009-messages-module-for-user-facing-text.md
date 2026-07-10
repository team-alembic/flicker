---
status: accepted
date: 2026-07-10
---

# ADR-009: All user-facing text routes through one overridable messages module; gettext optional

## Context

Flicker renders human-readable strings: empty states ("No results"),
loading hints, "clear all", chip-remove labels ("Remove Casey Nguyen"), and
— critically — screen-reader announcements ("5 results available", see
[Spec 007](../specs/spec-007-screen-reader-support.md)). Cinder needed a
whole `i18n/` layer for the same problem. Retrofitting string indirection
after strings are inlined across templates is miserable, so the mechanism
must exist before the first template is written. A hard gettext dependency
is unwanted weight for hosts that don't localise.

## Decision

A `Flicker.Messages` behaviour with a single callback:

```elixir
@callback message(key :: atom(), bindings :: map()) :: String.t()
# e.g. message(:results_count, %{count: 5}) => "5 results available"
```

- `Flicker.Messages.English` is the complete default implementation and the
  canonical list of every key (documented, so implementers can see exactly
  what to translate).
- Host override via `config :flicker, messages: MyAppWeb.FlickerMessages`
  and per-component attr; override modules can delegate unknown keys to the
  default.
- **Every** user-facing string — visible text *and* ARIA announcements —
  goes through `message/2`. No inline user-facing literals in templates;
  reviewers treat one as a defect.
- Gettext stays optional: a host's messages module may call its own gettext
  backend. Flicker neither depends on nor configures gettext.

Rejected: hard gettext dep (weight, and gettext's mix-task/POT workflow is
an app concern, not a library's); inline strings with a "we'll localise
later" plan (never happens cheaply); per-string component attrs (dozens of
attrs, and unusable for announcement strings).

## Consequences

- Adding a string means adding a key + English default — slight friction,
  total localisability, and the key list doubles as the announcement
  inventory Spec 007 audits.
- Message keys are public API once shipped (renaming one breaks host
  overrides) — covered by the public-contract rules in
  [DESIGN.md](../DESIGN.md#public-api--stability).
- Pluralisation stays simple (`count` bindings with per-key logic in the
  module); if a host needs CLDR plural rules, their override module is the
  place.
