if Code.ensure_loaded?(AshPhoenix.Form) do
  defmodule Flicker.AshPhoenixFormTest do
    @moduledoc """
    `Flicker.AshPhoenixForm.attach/2` must match a selection against the
    form's actual param name (`form.name`), not the socket assign key it
    lives under — those two only coincide by accident. `Flicker.Test.AshPhoenixFormHostLive`
    deliberately names its form `"artist"` while assigning it to `:form` to
    prove the mismatch case works.
    """

    # Shares the `Flicker.Test.PolicyDomain` seeded ETS table with
    # `Flicker.SelectAshTest` — `async: false` avoids a duplicate-seed race
    # against those concurrently running tests.
    use Flicker.Test.ConnCase, async: false

    import Flicker.Test.Helpers

    @moduletag :ash

    test "a selection lands in the AshPhoenix.Form even when its name differs from the assign key", %{conn: conn} do
      session =
        conn
        |> visit("/ash-phoenix-form")
        |> type_search("label-picker-input", "Casey Public")

      session = click_button(session, "Casey Public")

      assert_has(session, "#form-params", text: ~s("label" => ))
    end
  end
end
