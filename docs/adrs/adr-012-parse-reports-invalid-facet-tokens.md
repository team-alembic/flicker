---
status: proposed # proposed | accepted | superseded by adr-NNN
date: 2026-07-28
---

# ADR-012: `Query.parse/2` reports a known facet's uncastable value as invalid instead of degrading it to free text

## Context

Spec 003's parser has one failure mode: any token that doesn't cleanly become
a facet degrades — whole — to free text. That rule is deliberate and it is
what makes `Flicker.Query.parse/2` total: arbitrary typing never raises, and
a user who types `hello: world` gets a search for `hello: world` rather than
an error.

It also silently swallows real mistakes. `price:abc` on an integer facet does
not warn; it searches for the literal string `"price:abc"`, which matches
nothing, and the user is left staring at an empty result set with no idea the
facet was ignored. The same goes for `status:activ` (a typo on a closed enum),
`created:2026-13-01` (an impossible date), and — once
[Spec 018](../specs/spec-018-rich-facet-types.md) lands ranges —
`price:50..10` (reversed) and `price:10..` mid-typing.

These are not the same class of input as `hello: world`. The user named a
facet Flicker knows about, with an operator it allows, and got the value
wrong. There is enough information to say precisely what was expected.
Degrading it discards that information, and it is also the reason there is
currently nothing to gate dispatch on: an invalid facet isn't distinguishable
from ordinary prose.

## Decision

`Flicker.Query.parse/2` distinguishes two failure modes.

**Unknown territory still degrades.** An unrecognised key, an operator the
facet doesn't allow, malformed quoting, a token that isn't `key<op>value`
shaped at all — unchanged. Free text, as typed. Flicker has no basis for an
opinion about these, and this is the case that keeps the parser total.

**A known facet with a bad value is reported.** When the key names a facet in
the registry and the operator is legal for it but the value won't cast, the
token is neither a filter nor free text. It is recorded in a new
`%Flicker.Query{}` field, `:invalid` — a list of structs carrying the key, the
operator, the raw value, the verbatim token, and a machine-readable reason
plus params. It does not appear in `:facets` (so `to_filter/2` can never
include it) and it does not appear in `:text` (so it can never pollute the
free-text search).

Reasons are atoms with params, not sentences — `{:not_in_values, %{values:
[...]}}`, `{:reversed_range, %{from: ..., to: ...}}` — and
`Flicker.Messages` renders them, per [ADR-009](./adr-009-messages-module-for-user-facing-text.md).
Nothing in the parser produces user-facing English.

`parse/2` stays pure and total: an invalid token is a return value, never a
raise. `Flicker.Query.valid?/1` is `:invalid == []`, and that is the flag
components gate dispatch on.

Rejected alternatives:

- **Keep degrading; validate separately in the component.** Requires a second
  tokenizer and a second copy of the facet grammar in the component layer, and
  the two would drift. The parser already knows exactly which case it's in at
  the moment it decides.
- **Return `{:ok, query} | {:error, reasons}`.** Breaks every caller for the
  common case, and is wrong on the merits: a query with one bad token still has
  a perfectly good free-text portion and other valid facets to run with, and an
  in-progress token is *expected* to be invalid on most keystrokes.
- **Raise on invalid values.** A user mid-type would crash the LiveView. Never.
- **Opt in behind an option (`parse/3`).** Two behaviours to test, two to
  document, and the wrong one is the default. The degrade-to-text case is
  preserved where it belongs (unknown keys); the case being changed is one that
  produced a guaranteed-useless search.

## Consequences

Easier:

- Facet values can be validated and *explained*: the in-progress token renders
  as an error state with a real message, `aria-invalid` and
  `aria-describedby` (Spec 007), and the suggestion pop-out can say what shape
  it expected.
- Dispatch has something to gate on, **per facet**. A broken token invalidates
  itself and nothing else: it contributes no filter clause and renders as an
  error, while every other facet and the free text dispatch normally. Because
  `:invalid` is a list keyed by token rather than a query-level flag, a facet
  mid-type never freezes the results the user already has. `valid?/1` is a
  convenience for callers who do want the all-or-nothing reading, not the gate
  itself.
- Attribute constraints come along for free: `Ash.Type.apply_constraints/2` on
  a bounded integer or a `match`-constrained string yields a reason and params
  with no extra machinery.
- The rule is stated positively, so the failure taxonomy is closed and
  testable: every token lands in exactly one of `:facets`, `:text`, `:invalid`.

Harder:

- **This is a behaviour change to a documented contract.** Spec 003 and
  `Flicker.Query.parse/2`'s own `@doc` promise that *any* non-matching token
  degrades to free text. A caller relying on `price:abc` reaching `:text`
  loses that. It ships in a minor release with an explicit CHANGELOG
  behaviour-change note, and Spec 003's parse documentation is amended in the
  same change.
- Callers pattern-matching `%Flicker.Query{}` positionally or building one by
  hand gain a field. `:invalid` defaults to `[]`, so a hand-built query stays
  valid, but exhaustive struct literals in host code need updating.
- Every new facet type must define its failure reasons, not just its cast
  function, and every reason needs a `Flicker.Messages` entry — enforced the
  same way `Flicker.ThemeTest` enforces theme-part coverage.
- Per-facet independence means a query can dispatch *broader* than the user's
  typed intent while one facet is broken — they asked for two filters and got
  one. That is the right trade (better than freezing the results on a typo),
  but it puts real weight on the error being conspicuous and announced rather
  than a quiet outline.
- Free text can no longer be reconstructed as "everything that isn't a facet".
  Anything deriving text that way (or asserting on it in tests) has three
  buckets to account for instead of two.
