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

    # Regression (Spec 003 v1 scope cut, now lifted): "Jordan Blake" and
    # "Joey Turner" both match the free-text prefix "jo", but only "Joey
    # Turner" is `status: :active` — the completed `status:active` facet
    # token must narrow *which records* the free-text match considers, not
    # just strip itself out of the text sent to the provider.
    test "a completed facet token narrows the record search, not just the free text", %{conn: conn} do
      session = conn |> visit_as(%{label: nil}) |> type_search("artist-picker-input", "status:active jo")

      assert_has(session, "[role='option']", text: "Joey Turner")
      refute_has(session, "[role='option']", text: "Jordan Blake")
    end

    # Regression: spec-003's type table promises `:boolean` facets suggest
    # `true`/`false` — only `:enum` had value suggestions wired up. Covered
    # here (the `Flicker.select/1` surface) and in `Flicker.SearchTest` (the
    # `Flicker.search/1` surface) since both drive their own
    # `run_faceted_search`/`load_suggestions` clauses down to the same
    # `Flicker.FacetSuggest.enum_value_suggestions/2`.
    describe "facet-value autocomplete for a :boolean facet" do
      test "cursor at 'verified?:' suggests both true and false", %{conn: conn} do
        session = conn |> visit_as(%{label: nil}) |> type_search("artist-picker-input", "verified?:")

        assert_has(session, "[role='option']", text: "true")
        assert_has(session, "[role='option']", text: "false")
      end

      test "prefix filtering: 'verified?:f' suggests only false", %{conn: conn} do
        session = conn |> visit_as(%{label: nil}) |> type_search("artist-picker-input", "verified?:f")

        assert_has(session, "[role='option']", text: "false")
        refute_has(session, "[role='option']", text: "true")
      end
    end
  end
end
