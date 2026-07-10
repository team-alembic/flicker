# Flicker

[![CI](https://github.com/team-alembic/flicker/actions/workflows/elixir.yml/badge.svg)](https://github.com/team-alembic/flicker/actions/workflows/elixir.yml)
[![Hex version badge](https://img.shields.io/hexpm/v/flicker.svg)](https://hex.pm/packages/flicker)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/flicker)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> TODO: Replace this line with a one-sentence description of the package.

## Installation

Add `flicker` to the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flicker, "~> 0.1"}
  ]
end
```

## Usage

```elixir
Flicker.hello()
# => :world
```

See the [online documentation](https://hexdocs.pm/flicker) for more.

## Development

Requires Elixir / OTP as pinned in [`.tool-versions`](./.tool-versions).

```bash
mix deps.get
mix check        # full local quality suite
mix test         # just the tests
mix format       # format all files
```

Or use the included [devcontainer](./.devcontainer/devcontainer.json) — opens
with VS Code or any devcontainer-compatible editor and sets up Elixir + asdf
automatically.

## Releases

Releases are automated via [`git_ops`](https://hex.pm/packages/git_ops) and
conventional commits. To cut a release:

```bash
mix git_ops.release
git push && git push --tags
```

Then create a GitHub Release from the tag — the `release.yml` workflow
publishes to Hex on your behalf.

## License

Apache 2.0. See [LICENSE](./LICENSE).

---

<sub>This repository was generated from [team-alembic/elixir_package_template](https://github.com/team-alembic/elixir_package_template).</sub>
