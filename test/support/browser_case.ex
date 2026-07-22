if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Test.BrowserCase do
    @moduledoc """
    Shared case template for Spec 007's browser-driven suite: axe-core scans
    (`test/flicker/browser/axe_test.exs`) and the client-side keyboard
    behaviour ExUnit/PhoenixTest can't reach — real arrow-key/`Enter`/
    `aria-activedescendant`/focus-trap DOM behaviour
    (`test/flicker/browser/keyboard_test.exs`).

    `use`s `Wallaby.Feature` and tags every test `:browser` — excluded from
    the default `mix test` run (`test/test_helper.exs`) and run on their
    own via `mix test --only browser` (a local chromedriver, or the
    dedicated CI job in `.github/workflows/elixir.yml`).

    Boots `Dev.Endpoint` (the dev playground, Spec 005) for real over HTTP
    — axe-core and Wallaby both need an actually-rendered DOM, which
    `Flicker.Test.ConnCase`'s in-process `Phoenix.ConnTest` dispatch can't
    give them — plus the `:wallaby` application itself, both idempotently
    (every test module `use`-ing this case runs the same `setup_all`).
    Only ever reached when a `:browser`-tagged test is actually selected to
    run, so it never affects the default suite or the no-ash leg (`dev/`,
    and this module, aren't even compiled there).
    """

    use ExUnit.CaseTemplate

    using do
      quote do
        use Wallaby.Feature

        @moduletag :browser
      end
    end

    setup_all do
      ensure_dev_endpoint_started()
      {:ok, _apps} = Application.ensure_all_started(:wallaby)
      :ok
    end

    @doc false
    @spec ensure_dev_endpoint_started() :: :ok
    def ensure_dev_endpoint_started do
      case Phoenix.PubSub.Supervisor.start_link(name: Dev.PubSub) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      case Dev.Endpoint.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end
  end
end
