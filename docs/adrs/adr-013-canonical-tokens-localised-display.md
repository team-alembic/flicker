---
status: proposed # proposed | accepted | superseded by adr-NNN
date: 2026-07-28
---

# ADR-013: Facet tokens are locale-invariant; localisation is a display and input-affordance layer, via optional `localize`

## Context

[Spec 018](../specs/spec-018-rich-facet-types.md) introduces facet values with
real structure — date and datetime ranges, numeric ranges, durations,
multi-value enums — and [ADR-011](./adr-011-facet-editors-are-modal-subcontexts.md)
gives them rich editors. All of that has a presentation problem the current
code answers in hardcoded en-US:

- Spec 018 hardcodes Monday as the first day of the week. CLDR says Sunday in
  the US, Saturday across much of MENA, and `this-week`/`last-week` resolve to
  different dates accordingly.
- A `%Facet.Range{}` pill has to render as one legible interval, and the
  intelligent collapsing (`Jun 18 – Jul 12`, `18–24 Jul 2026`) is per-locale
  CLDR data, not string concatenation.
- Numeric casting uses `Integer.parse/1` and `Float.parse/1`, which understand
  `.` as the decimal separator and nothing else.
- Multi-value pills need a locale conjunction (`Active, Pending and Archived`).
- Preset labels, duration formatting, and validation messages are English
  literals.

The `localize` package (the CLDR family: `Localize.Interval`,
`Localize.Calendar`, `Localize.Number`, `Localize.Duration`, `Localize.List`,
`Localize.Collation`, `Localize.DateTime.Relative`, `Localize.Message`) answers
every one of these directly.

But localisation collides with a guarantee. ADR-011 makes `Flicker.Query.input`
the canonical, re-parseable source of truth, and Spec 009 Level 2 puts it in the
URL. If parsing were locale-aware, that string would stop denoting one thing:
`price:1.234` is 1234 in de-DE and 1.234 in en-AU; `created:06/18/2026` is a
different day read as D/M/Y than as M/D/Y. A bookmarked or shared query would
silently resolve differently depending on who opened it.

## Decision

**The token grammar is locale-invariant. Localisation is display, plus input
affordances that serialise back to canonical form.**

Concretely:

- **On the wire** — dates and datetimes are ISO 8601, the decimal separator is
  `.`, list elements are comma-separated, ranges use `..`, and preset and enum
  values are their canonical ids. This is what an editor emits, what
  `Flicker.Query.parse/2` accepts, what `:input` holds, and what appears in a
  URL. `Flicker.Query.parse/2` takes **no locale argument** and stays a pure
  function of `(input, facets)`.
- **On screen** — everything is localised: calendar month and weekday names and
  the locale's own first day of week, interval-formatted range pills, locale
  number and duration formatting, locale list conjunctions, collated value
  lists, and validation messages via ICU MessageFormat 2.
- **At the keyboard** — a rich editor is where locale-native *input* lives. A
  German user picks dates from a German calendar and types `1.234,56` into a
  numeric field; the editor normalises on commit and splices canonical token
  text (per ADR-011, an editor's only output is token text). Hand-typed
  free-form tokens in the main input remain canonical-only.

**Preset ids are canonical; their resolution is contextual.** `last-week`
serialises as `last-week` always, and resolves against both a reference date
*and* the active locale's week rules. That a relative preset resolves
differently tomorrow, or in a different locale, is the intended semantic — the
same reason presets serialise as ids rather than resolved dates.

**`localize` is an optional dependency**, carried exactly like `ash` under
[ADR-006](./adr-006-core-depends-only-on-provider.md): `optional: true`,
guarded with `Code.ensure_loaded?(Localize)`. Absent, Flicker keeps today's
ISO/English behaviour with no degradation in function. Present, every display
path localises. Formatting is reached through one module (and, for text,
`Flicker.Messages` per [ADR-009](./adr-009-messages-module-for-user-facing-text.md)),
never called ad hoc from components — so the fallback exists in one place per
concern rather than at every call site.

**Locale is resolved per component, not per process.**
`Localize.put_locale/1` is process-scoped, which is a poor fit for a component
that may format values in an async assign or a different process than the one
that mounted. Flicker's components take a `locale` attr defaulting to
`Localize.get_locale/0`, and pass it explicitly into every formatting call.

Rejected alternatives:

- **Fully localised tokens** — the natural thing to type and read, but it
  breaks the round-trip ADR-011 and Spec 009 depend on. Every persisted query
  would need its locale stored beside it, and a shared URL would mean different
  things to different viewers. Non-starter for a filter you can bookmark.
- **Canonical wire plus locale-tolerant parsing of hand-typed values** —
  attractive, and deliberately left as a possible future addition, but it makes
  `parse/2` locale-dependent (a locale argument, and its property-test matrix
  multiplied by the locale set) and forces an arbitrary ambiguity rule for
  `06/18` in locales where both readings are plausible. Rich editors already
  cover the typist's ergonomics for exactly the types where formats diverge.
- **`localize` as a required dependency** — one code path and no compile guards,
  but every Flicker user pays for CLDR data and compile time whether they
  localise or not. Contradicts the dependency-light posture ADR-006 sets.
- **Localising via `gettext` alone** — handles message strings, but has nothing
  to say about interval collapsing, week rules, collation, plural-aware
  durations, or number parsing, which is most of the actual problem.

## Consequences

Easier:

- The round-trip guarantee survives intact: URL state, Cinder interop,
  `to_filter/2`, and every parser property test are untouched by localisation,
  because the parser never sees a locale.
- Localisation lands as one testable seam. A formatter module with a
  with-`localize` and without-`localize` implementation, exercised the same way
  the no-ash CI matrix already exercises ADR-006's boundary.
- Rich editors gain a clear reason to exist beyond convenience: they are where
  locale-native input is possible at all, which strengthens ADR-011 rather than
  complicating it.
- The Spec 018 preset list stops needing English labels in the spec at all —
  `Localize.DateTime.Relative` and `Localize.Interval` supply them.

Harder:

- **Display and wire form diverge visibly.** A de-DE user picks a range from a
  German calendar and then sees `created:2026-06-18..2026-07-12` if they look at
  the raw input. Spec 012's pills are what make this a non-issue in practice
  (the committed facet reads as a localised interval, not as a token), so pills
  move from "nice rendering" to load-bearing for a localised UI.
- Hand-typing a date in the main input requires ISO form. Acceptable, and it is
  the one place localisation stops.
- Every formatting concern needs two implementations — CLDR and fallback — and a
  CI matrix cell without `localize` to prove the fallback still compiles and
  reads sensibly.
- Week-sensitive presets (`this-week`, `last-week`) resolve differently per
  locale, so their tests must fix both a reference date *and* a locale. Every
  other preset needs only the date.
- Adding a fourth optional-dependency boundary (`ash`, `gettext`,
  `phoenix_live_view` floors, now `localize`) grows the compile-guard surface
  and the CI matrix; worth watching before a fifth is added.
