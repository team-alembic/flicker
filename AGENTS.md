# AGENTS.md

Guidance for AI agents (Claude Code, Factory, Copilot, Cursor, ...) working in
this repository. This file is the source of truth; `CLAUDE.md` forwards to it.

## Project

`flicker` is an Ash-native searchable select / combobox / faceted-search
component for Phoenix LiveView — what Cinder is for tables, Flicker is for
searching, filtering, and selecting records. It reads directly off Ash
resources (no options plumbing), authorises via `actor:` + policies, derives
facet behaviour from the Ash type system, and installs via Igniter.

It is an Elixir library distributed via Hex. Keep the public API small,
documented, and backwards-compatible between minor releases.

## Documentation map

Contributor/agent-facing docs live in `docs/` (not shipped to hexdocs);
`guides/` is the user-facing hexdocs surface.

- [`docs/DESIGN.md`](./docs/DESIGN.md) — north star: what Flicker is, why,
  build sequencing, cross-cutting open questions.
- [`docs/specs/`](./docs/specs/README.md) — feature specs, numbered, each
  implementable from the spec alone. The index README lists every spec with
  status (`draft`/`ready`/`in-progress`/`shipped`).
- [`docs/adrs/`](./docs/adrs/README.md) — architecture decision records,
  numbered, append-only. The index README lists every ADR with status.

### Doc lifecycle rules

- **Before implementing a feature**: read its spec (check the specs index).
  If no spec exists, write one from `docs/specs/TEMPLATE.md` first — or flag
  that one is needed — rather than implementing from a vague prompt.
- **Starting / finishing spec work**: flip its status to `in-progress` /
  `shipped` in the frontmatter **and** the index row.
- **Making a structural or public-API decision** not covered by an existing
  ADR: add one from `docs/adrs/TEMPLATE.md` in the same PR, and index it.
- **ADRs are append-only**: never edit an accepted decision — write a
  superseding ADR and update both status lines and the index.
- **Cross-link**: specs list the ADRs they build on (`depends_on`
  frontmatter + inline links); ADRs link back to motivating specs.

## Stack

| Layer       | Choice                                  |
|-------------|-----------------------------------------|
| Language    | Elixir (see `.tool-versions`)           |
| Lint        | Credo strict mode (`mix credo --strict`, or `mix lint` when `ash_credo` is on) |
| Types       | Dialyxir (`mix dialyzer`)               |
| Test        | ExUnit (`mix test`)                     |
| Docs        | ExDoc (`mix docs`)                      |
| Style       | `mix format` + Quokka (enforced in CI)  |
| Security    | Sobelow, `mix hex.audit`, `mix deps.audit` |
| Coverage    | Doctor doc-coverage (`mix doctor`)      |
| Release     | `git_ops` (conventional commits → tag + CHANGELOG) |
| Agent rules | `usage_rules` (skills mode)             |

## Agent skills

Runtime agent knowledge lives in `.claude/skills/` and is generated from
`deps/*/usage-rules.md` files by `mix usage_rules.sync`. See the `usage_rules`
block in `mix.exs` for the config (deps, package_skills, and composed skills).

- **Run after adding / removing deps**: `mix usage_rules.sync`
- **Skills are committed** — downstream collaborators don't need to re-sync on
  clone. Stale skills are pruned automatically when the config changes.
- **Customising a generated skill**: write content above the
  `<!-- usage-rules-skill-start -->` marker in any SKILL.md; custom content is
  preserved across syncs.

Skills are auto-discovered by Claude Code once the file exists — no extra
registration needed.

## Common commands

```bash
mix deps.get
mix check                      # full local quality suite
mix test                       # just the tests
mix test test/path_test.exs:42
mix test.watch                 # re-run tests on file change
mix format
mix format --check-formatted
mix credo --strict
mix dialyzer
mix docs
mix usage_rules.sync           # regenerate .claude/skills/ from deps

# Spec 007's browser-driven suite (axe-core + client-side keyboard
# behaviour) — excluded from `mix test`/`mix check`, needs a real Chrome +
# chromedriver on PATH (`brew install --cask chromedriver` on macOS, or
# CI's `browser` job). Boots `Dev.Endpoint` for real over HTTP itself —
# see `test/support/browser_case.ex`.
mix test --only browser
```

## Rules

### Before writing code
1. Read the relevant spec in `docs/specs/` and the ADRs it links (see
   [Documentation map](#documentation-map) above).
2. Check for a relevant generated skill in `.claude/skills/` or invoke one of
   the `alembic-elixir-ash` plugin skills (`ash-framework`, `elixir-style`,
   `phoenix-liveview`, `postgres-patterns`).
3. Prefer editing existing modules over creating new ones.
4. Search `deps/*/usage-rules.md` with `mix usage_rules.search_docs` for
   package-specific guidance that isn't in a skill yet.

### While writing code
- Every public function has a `@doc`.
- Every module has a `@moduledoc`.
- Prefer pattern matching and `with` over nested `case`/`if`.
- Let it crash; supervise.
- No compiler warnings. CI runs with `--warnings-as-errors`.
- `snake_case` for variables, `CamelCase` for modules.
- Comments only when the *why* is non-obvious.

### Git workflow
- Trunk-based: commit directly to `main`, no branches or PRs for now.
  Git is for history — commit in small logical units and **push after
  every work session** (`git push`).

### Before committing
- `mix format` and `mix credo --strict` must pass.
- Add or update tests for any behavior change.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `ci:`.
- Update `usage-rules.md` if the change affects how downstream consumers use
  this package.
- **Do not** edit `CHANGELOG.md` by hand — `mix git_ops.release` generates it.

## Package-specific rules

See [`usage-rules.md`](./usage-rules.md) for the rules this package publishes
to its consumers.

## Recommended Claude Code plugins

Install the Alembic marketplace once per machine, then these plugins per
project:

```
/plugin marketplace add team-alembic/alembic-claude-tools
/plugin install alembic-core@alembic-claude-tools
/plugin install alembic-elixir-ash@alembic-claude-tools
/plugin install alembic-reviewer@alembic-claude-tools
```

- **`alembic-core`** — `/plan`, `/work`, `/review`, `/compound`, worktree,
  skill-creator.
- **`alembic-elixir-ash`** — Elixir/Ash/Phoenix/Postgres skills + reviewers +
  `/sync-ash-rules`.
- **`alembic-reviewer`** — security, performance, data-integrity reviewers.
