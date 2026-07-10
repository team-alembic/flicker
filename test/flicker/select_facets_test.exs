if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SelectFacetsTest do
    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers

    @moduletag :ash

    defp visit_as(conn, actor) do
      conn = Plug.Test.init_test_session(conn, %{"actor" => actor})
      visit(conn, "/facet-select")
    end

    test "typing a facet key shows key suggestions instead of record results", %{conn: conn} do
      session = conn |> visit_as(%{label: nil}) |> type_search("artist-picker-input", "stat")

      assert_has(session, "[role='option']", text: "status:")
      refute_has(session, "[role='option']", text: "Riley Rivers")
    end

    test "picking a facet-key suggestion edits the text instead of selecting a record", %{conn: conn} do
      session = conn |> visit_as(%{label: nil}) |> type_search("artist-picker-input", "stat")

      session = click_button(session, "status:")

      assert_has(session, "#artist-picker-input[value='status:']")
      refute_has(session, "#selection")
    end

    test "picking a facet-value suggestion completes the token instead of selecting a record", %{conn: conn} do
      session = conn |> visit_as(%{label: nil}) |> type_search("artist-picker-input", "status:")

      session = click_button(session, "Active")

      assert_has(session, "#artist-picker-input[value='status:active ']")
      refute_has(session, "#selection")
    end

    test "free text after a completed facet still selects a record normally", %{conn: conn} do
      session = conn |> visit_as(%{label: nil}) |> type_search("artist-picker-input", "status:active Riley")

      session = click_button(session, "Riley Rivers")

      assert_has(session, "#selection", text: "Riley Rivers")
    end
  end
end
