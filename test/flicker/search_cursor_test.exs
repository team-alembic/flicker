if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchCursorTest do
    @moduledoc """
    Closes spec-003's last v1 scope cut: `Flicker.CursorContext.classify/3`
    always supported an arbitrary cursor position, but `Flicker.search/1`
    wired plain `phx-keyup` payloads (no `selectionStart`) and always
    classified as if the caret sat at the end of the typed text. The
    colocated `.FlickerSearchNav` hook now reports the real position
    (`phx-value-cursor` merged into the debounced "query" push, or the
    lightweight "cursor" event on click/select) — these tests drive that
    payload directly (`Flicker.Test.Helpers.type_search_at/4`, mirroring
    what the hook sends) through the full component, not just
    `Flicker.CursorContext`/`Flicker.FacetSuggest` in isolation.
    """

    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers

    @moduletag :ash

    defp visit_as(conn, actor) do
      conn = Plug.Test.init_test_session(conn, %{"actor" => actor})
      visit(conn, "/facet-search")
    end

    describe "a mid-token cursor position" do
      # "status:activ verified?:true" — the caret is placed inside the
      # *first* (`status`) token's value, even though a second, completed
      # facet token (`verified?:true`, a `:boolean` facet) follows it.
      # Assuming end-of-text (the lifted v1 cut) would classify the cursor
      # as sitting inside `verified?:true` instead — a different facet
      # with a different (boolean) picklist entirely — so the presence of
      # the enum suggestion and the absence of the boolean one is a clean,
      # observable proof the real position drives classification, not the
      # end of the text.
      test "classifies at the real caret, not the end of the text", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search_at("artist-search-input", "status:activ verified?:true", 11)

        assert_has(session, "[role='option']", text: "Active")
        refute_has(session, "[role='option']", text: "true")
        refute_has(session, "[role='option']", text: "false")
      end

      test "moving the cursor back into a completed key without retyping still resuggests its values",
           %{conn: conn} do
        # Cursor 4 sits inside "stat" of the completed "status" key — still
        # `{:key, "stat"}`, key suggestions, not a value picklist.
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search_at("artist-search-input", "status:active", 4)

        assert_has(session, "[role='option']", text: "status:")
      end
    end

    describe "an omitted cursor position (regression)" do
      # No "cursor" key in the event payload at all — the dead-render /
      # very first-keystroke case, before the hook has reported one yet.
      # Must fall back to end-of-text exactly as `Flicker.search/1` always
      # has, not crash and not misclassify.
      test "falls back to classifying at the end of the text", %{conn: conn} do
        session = conn |> visit_as(%{label: nil}) |> type_search("artist-search-input", "stat")

        assert_has(session, "[role='option']", text: "status:")
      end

      test "an omitted cursor still lets a completed facet narrow the free-text match", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:active")

        session = click_button(session, "Active")

        assert_has(session, "#artist-search-input[value='status:active ']")
        assert_has(session, "#last-facets", text: "{:status, :eq, :active}")
      end
    end
  end
end
