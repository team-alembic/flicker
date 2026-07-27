---
status: accepted
date: 2026-07-24
---

# ADR-010: The installer wires JS with igniter_js, CSS and config with plain text patches — no igniter_css

## Context

`mix flicker.install` ([ADR-007](./adr-007-colocated-js-hook.md)) edits a
handful of host files: the formatter, `config/config.exs`, `assets/js/app.js`
(the colocated-hook import + `LiveSocket` `hooks` merge), and a Tailwind
source registration so Flicker's utility classes survive the content purge.

Each edit could be done at three levels of rigour: string/regex patching, an
AST codemod, or a framework helper. The Ash-adjacent ecosystem offers two
NIF-backed codemod packages for the file types we touch:

- `igniter_js` — a Rust parser with purpose-built LiveView helpers
  (`insert_imports/2`, `extend_hook_object/2`).
- `igniter_css` — a Python parser for CSS codemods.

The `app.js` edit is genuinely structural: it has to find the `LiveSocket`
call and merge into its `hooks` object, which regex does badly (the previous
implementation was fragile and self-admittedly so). The Tailwind edit is not:
it appends one `@source` directive (v4) or one glob string to a `content:`
array (v3).

## Decision

The installer uses `igniter_js` for the `app.js` hook wiring and plain-text
patches (guarded by a `String.contains?` idempotency marker, with a
manual-edit notice on no match) for everything else — config, formatter, and
the Tailwind source directive. Flicker does **not** depend on `igniter_css`.

Both codemod deps are optional and dev/test-only; `igniter_js` isn't
inherited by a host that merely depends on Flicker, so the installer detects
its absence, adds it to the host's dev deps, and asks for a re-run.

Rejected: `igniter_css` for the Tailwind step. It would pull a second
precompiled NIF (and a Python toolchain in its build) into the install path
to insert a single line that a `Rewrite.Source` content update already
handles idempotently. The AST rigour buys nothing for a one-line append —
there is no surrounding structure to reason about, unlike the `LiveSocket`
object. The cost/benefit that justifies `igniter_js` for JS inverts for CSS.

Rejected: regex for `app.js` too (uniformity). The `LiveSocket` merge is
exactly the structural case regex handles poorly; keeping the tools matched
to the shape of each edit beats a consistent-but-worse approach.

## Consequences

- One codemod dependency (`igniter_js`), not two. The install path stays
  lighter and avoids a Python build toolchain.
- The Tailwind step is a plain text transform: easy to read, test against
  fixtures, and reason about, at the cost of being format-sensitive — it
  keys off `@import "tailwindcss"` (v4) or `content: [` (v3) and falls back
  to a printed manual edit when neither matches.
- If the Tailwind edit ever grows structural needs (reordering layers,
  editing existing directives rather than appending), this decision should
  be revisited — that's the point at which `igniter_css` earns its weight.
- The asymmetry (AST for JS, text for CSS) is deliberate and documented here
  so it doesn't read as an oversight.

Related: [ADR-007](./adr-007-colocated-js-hook.md),
[Spec 001](../specs/spec-001-portable-single-select.md).
