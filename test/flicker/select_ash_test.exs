if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SelectAshTest do
    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers

    @moduletag :ash

    # `Flicker.Test.AshHostLive` seeds `Flicker.Test.PolicyArtist` in its own
    # `mount/3` (idempotent — safe however many test processes call it).
    # "Alex Cassidy" is label: "indie" — visible only to an actor whose own
    # label matches.
    defp visit_as(conn, actor) do
      conn = Plug.Test.init_test_session(conn, %{"actor" => actor})
      visit(conn, "/ash")
    end

    test "an actor who can read the record sees it in search results", %{conn: conn} do
      session =
        conn
        |> visit_as(%{label: "indie"})
        |> type_search("artist-picker-input", "Alex Cassidy")

      assert_has(session, "[role='option']", text: "Alex Cassidy")
    end

    test "an actor a policy hides the record from never sees it", %{conn: conn} do
      session =
        conn
        |> visit_as(%{label: "major"})
        |> type_search("artist-picker-input", "Alex Cassidy")

      refute_has(session, "[role='option']", text: "Alex Cassidy")
    end

    test "the public actor (no label) never sees a labelled record", %{conn: conn} do
      session =
        conn
        |> visit_as(%{label: nil})
        |> type_search("artist-picker-input", "Alex Cassidy")

      refute_has(session, "[role='option']", text: "Alex Cassidy")
    end
  end
end
