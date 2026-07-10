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

ExUnit.start()
