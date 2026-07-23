if Code.ensure_loaded?(PhoenixTest) do
  defmodule Flicker.Test do
    @moduledoc """
    A `PhoenixTest` helper for driving `Flicker.select/1` the way a user
    would: open the picker, type to filter, pick a result.

    Flicker does not depend on `phoenix_test` itself — this module simply
    doesn't compile without it (see the `Code.ensure_loaded?/1` guard around
    it). Add `{:phoenix_test, "~> 0.5", only: :test}` to your own `mix.exs`
    to use it (most PhoenixTest users already have it).
    """

    import Phoenix.LiveViewTest,
      only: [element: 2, render_async: 1, render_focus: 1, render_keyup: 2]

    @doc """
    Opens the picker identified by its required component `id`, types
    `option_text` into it to filter, then clicks the resulting option of
    the same text.

    Returns the `session` for further `PhoenixTest` chaining.

    ## Example

        session
        |> Flicker.Test.search_select("client-select", "Casey Cassidy")
        |> PhoenixTest.assert_has("#selection", text: "Casey Cassidy")
    """
    @spec search_select(struct(), String.t(), String.t()) :: struct()
    def search_select(session, select_id, option_text) do
      session.view
      |> element("##{select_id}-input")
      |> render_focus()

      session.view
      |> element("##{select_id}-input")
      |> render_keyup(%{"value" => option_text})

      render_async(session.view)

      PhoenixTest.click_button(session, option_text)
    end
  end
end
