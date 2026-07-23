---
status: in-progress # draft | ready | in-progress | shipped
date: 2026-07-23
depends_on: [spec-005] # dev playground
---

# Spec 014: Copyable example code blocks in the playground

Each playground example shows its own source in a copy-to-clipboard code
block, the way component-library docs (shadcn/ui, daisyUI, Radix) present
"here's the component, here's the code". A visitor can read what produced the
live example and paste it straight into their app.

## Scope

- A `<.code_example>` component in `Dev.UI`: renders a live example and,
  beneath (or in a "Code" toggle), the exact source that produced it, in a
  styled block with a **Copy** button (copies to clipboard, shows "Copied").
- Applied to the key capability pages (single-select, multi-select, faceted
  search, palette) — each `.section`'s example gains its code.
- Copy uses a tiny colocated JS hook (`navigator.clipboard.writeText`); no new
  runtime dep. Framework-free per ADR-002.

## Non-goals

- No syntax-highlighting engine dependency in v1 — a monospace block with
  minimal token styling is enough (revisit highlighting later).
- Not auto-extracting source from the module at compile time in v1 (nice, but
  fragile); the code shown is passed explicitly to `<.code_example code={…}>`
  as a heredoc string kept next to the example. (Auto-extraction is an open
  question below.)
- Playground/docs only — nothing shipped in the library's runtime.

## Design

```heex
<.code_example code={~S'''
<Flicker.select id="artist" resource={Artist} search={[:name]} option_label={:name} />
'''}>
  <Flicker.select id="artist" resource={Artist} search={[:name]} option_label={:name} />
</.code_example>
```

Renders the `inner_block` (the live example) then a `<pre>` of `code` with a
Copy button wired to a `.CopyCode` colocated hook. Themed with the
playground's existing Tailwind chrome (`Dev.UI`), not the library theme.

## Acceptance criteria

- [ ] Each wrapped example shows its live render plus a code block.
- [ ] The Copy button copies the shown code and gives visible feedback.
- [ ] Works without external JS/CDN (inline colocated hook).
- [ ] Code shown matches what renders (kept in sync by living next to it).

## Open questions

- Auto-extract example source at compile time (macro/`__ENV__`) so the shown
  code can't drift from the live one — worth a follow-up, out of v1 scope.
- Should this also generate the hexdocs `guides/` snippets, or stay
  playground-only?
