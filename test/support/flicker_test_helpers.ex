defmodule Flicker.Test.Helpers do
  @moduledoc """
  PhoenixTest helpers for driving `Flicker.select/1`.

  `Flicker.select/1`'s search input binds `phx-keyup` directly (not
  `phx-change` on an ancestor `<form>`, since controlled mode renders no
  form at all) — outside what `PhoenixTest.fill_in/3` supports (it
  unconditionally requires a `<form>` ancestor). `type_search/3` drives the
  same keyup event `Phoenix.LiveViewTest` would, one level below
  `PhoenixTest`, and returns a `PhoenixTest` session so it composes with
  every other `PhoenixTest` helper.
  """

  import Phoenix.LiveViewTest

  # `render_async/2`'s default timeout is `ExUnit`'s `assert_receive_timeout`
  # (100ms) — plenty when a search task is pure in-memory work, but the
  # Ash-backed suites route it through `Ash.Policy.Authorizer` over a real
  # (shared, non-private) ETS table, and under `mix test`'s full parallel
  # load that authorization + read can take longer than 100ms. A generous
  # fixed timeout here keeps the wait tied to actual task completion (still
  # a `Process` `:DOWN` await, not a blind sleep) without weakening
  # `assert_receive_timeout` for every other assertion in the suite.
  @search_timeout 2_000

  @doc """
  Types `text` into the Flicker search input identified by `input_id` (e.g.
  `"picker-input"`), then awaits the resulting search's `start_async` task
  (searches run asynchronously — see `Flicker.Components.Select`) before
  returning, so the caller's next assertion sees the loaded results rather
  than racing the in-flight task.
  """
  @spec type_search(struct(), String.t(), String.t()) :: struct()
  def type_search(session, input_id, text) do
    session.view
    |> element("##{input_id}")
    |> render_keyup(%{"value" => text})

    render_async(session.view, @search_timeout)

    session
  end
end
