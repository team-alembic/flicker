if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SelectCursorTest do
    @moduledoc """
    The `Flicker.select/1` counterpart of `Flicker.SearchCursorTest` —
    closes the same spec-003 v1 scope cut (real cursor-position reporting)
    for the `facets` attr on `Flicker.select/1`, which drives the same
    `Flicker.CursorContext`/`Flicker.FacetSuggest` machinery through its
    own `.Nav` colocated hook and `"query"`/`"cursor"` events.
    """

    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers

    @moduletag :ash

    defp visit_as(conn, actor) do
      conn = Plug.Test.init_test_session(conn, %{"actor" => actor})
      visit(conn, "/facet-select")
    end

    describe "a mid-token cursor position" do
      test "classifies at the real caret, not the end of the text", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search_at("artist-picker-input", "status:activ verified?:true", 11)

        assert_has(session, "[role='option']", text: "Active")
        refute_has(session, "[role='option']", text: "true")
        refute_has(session, "[role='option']", text: "false")
      end
    end

    describe "an omitted cursor position (regression)" do
      test "falls back to classifying at the end of the text", %{conn: conn} do
        session = conn |> visit_as(%{label: nil}) |> type_search("artist-picker-input", "stat")

        assert_has(session, "[role='option']", text: "status:")
        refute_has(session, "[role='option']", text: "Riley Rivers")
      end
    end
  end
end
