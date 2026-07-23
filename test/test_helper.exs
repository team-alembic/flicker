# Ash logs each create/read at :debug by default — quiet by default so
# `Dev.Music.seed!/0` (called in most Ash-provider test setups) doesn't
# drown out actual test output; bump back down locally when debugging.
Logger.configure(level: :info)

# `Flicker.Test.Endpoint` (test/support) backs the PhoenixTest-driven
# component tests (Spec 001 onward) — started once here, never as a real
# HTTP listener (`server: false`), just enough for `Phoenix.ConnTest`'s
# in-process dispatch and LiveView's PubSub-based diffing.
{:ok, _pubsub} = Phoenix.PubSub.Supervisor.start_link(name: Flicker.Test.PubSub)
{:ok, _endpoint} = Flicker.Test.Endpoint.start_link()

# Ash's shared ETS table manager registers before its table is ready. Seed
# before ExUnit starts so async tests cannot observe that startup window.
if Code.ensure_loaded?(Dev.Music) do
  Dev.Music.seed!()
end

# Spec 007's browser-driven suite (`test/flicker/browser/`, `@moduletag
# :browser`) needs a real browser + chromedriver most contributors don't
# have installed, so it's excluded here by default. `mix test --only
# browser` still runs it — `ExUnit.Filters.normalize/2` cancels a
# statically configured exclude for any tag also passed to `--only`/
# `--include`, the same mechanism `--only external`-style suites use
# elsewhere (see `mix help test`).
ExUnit.start(exclude: [:browser])
