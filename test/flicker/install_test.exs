defmodule Flicker.InstallTest do
  @moduledoc """
  Exercises `mix igniter.install flicker`'s patches (Spec 001's installer
  acceptance criterion) via `Igniter.Test`.
  """

  # `Igniter.Test.test_project/1` pushes a synthetic Mix.Project onto the
  # global project stack — concurrent installs collide.
  use ExUnit.Case, async: false

  import Igniter.Test

  @app_js """
  import "phoenix_html"
  import {Socket} from "phoenix"
  import {LiveSocket} from "phoenix_live_view"
  import {hooks as colocatedHooks} from "phoenix-colocated/test"
  import topbar from "../vendor/topbar"

  const liveSocket = new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: {...colocatedHooks},
  })
  """

  defp install(files \\ %{}) do
    [files: files]
    |> test_project()
    |> Mix.Tasks.Flicker.Install.igniter()
  end

  defp assert_diff_contains(igniter, path, text) do
    assert diff(igniter, only: path) =~ text
  end

  test "imports :flicker into the formatter" do
    igniter = install()

    assert_diff_contains(igniter, ".formatter.exs", "import_deps: [:flicker]")
  end

  test "configures default_limit and default_debounce" do
    igniter = install()

    assert_diff_contains(igniter, "config/config.exs", "default_limit: 25")
    assert_diff_contains(igniter, "config/config.exs", "default_debounce: 150")
  end

  test "does not overwrite an already-configured key" do
    igniter =
      install(%{
        "config/config.exs" => """
        import Config
        config :flicker, default_limit: 100
        """
      })

    assert_diff_contains(igniter, "config/config.exs", "default_debounce: 150")
    refute diff(igniter, only: "config/config.exs") =~ "default_limit: 25"
  end

  describe "assets/js/app.js" do
    test "wires the colocated hook import and merges it into the LiveSocket hooks option" do
      igniter = install(%{"assets/js/app.js" => @app_js})

      assert_diff_contains(igniter, "assets/js/app.js", "phoenix-colocated/flicker")
      assert_diff_contains(igniter, "assets/js/app.js", "...flickerHooks")
    end

    test "is idempotent when the import already exists" do
      already_wired =
        String.replace(@app_js, "hooks: {...colocatedHooks},", "hooks: {...colocatedHooks, ...flickerHooks},")

      already_wired =
        String.replace(
          already_wired,
          ~s|import {hooks as colocatedHooks} from "phoenix-colocated/test"|,
          ~s|import {hooks as colocatedHooks} from "phoenix-colocated/test"\nimport {hooks as flickerHooks} from "phoenix-colocated/flicker"|
        )

      igniter = install(%{"assets/js/app.js" => already_wired})

      assert_unchanged(igniter, "assets/js/app.js")
    end

    test "leaves a notice when app.js doesn't exist" do
      igniter = install()

      assert_has_notice(igniter, &String.contains?(&1, "flickerHooks"))
    end
  end
end
