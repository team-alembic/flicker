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
    Opens the picker identified by `trigger_text` — its placeholder prompt
    when nothing is selected, or the currently selected option's label once
    one is — types `option_text` into it to filter, then clicks the
    resulting option of the same text.

    Returns the `session` for further `PhoenixTest` chaining.

    ## Example

        session
        |> Flicker.Test.search_select("Search...", "Casey Cassidy")
        |> PhoenixTest.assert_has("#selection", text: "Casey Cassidy")
    """
    @spec search_select(struct(), String.t(), String.t()) :: struct()
    def search_select(session, trigger_text, option_text) do
      trigger_selector =
        ~s(input[placeholder=#{inspect(trigger_text)}],input[value=#{inspect(trigger_text)}])

      session.view |> element(trigger_selector) |> render_focus()

      # Opening resets the input's value to "" (a fresh search), so the
      # trigger selector above (matched on the pre-open placeholder/value
      # text) no longer identifies it — `aria-expanded` does once open.
      session.view
      |> element(~s(input[role="combobox"][aria-expanded="true"]))
      |> render_keyup(%{"value" => option_text})

      render_async(session.view)

      PhoenixTest.click_button(session, option_text)
    end
  end
end
