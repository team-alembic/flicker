if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchTest do
    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers

    @moduletag :ash

    defp visit_as(conn, actor) do
      conn = Plug.Test.init_test_session(conn, %{"actor" => actor})
      visit(conn, "/facet-search")
    end

    describe "facet-key autocomplete" do
      test "'stat' suggests 'status:'", %{conn: conn} do
        session = conn |> visit_as(%{label: nil}) |> type_search("artist-search-input", "stat")
        assert_has(session, "[role='option']", text: "status:")
      end

      test "picking a key suggestion inserts 'status:' and opens the value picklist", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "stat")

        session = click_button(session, "status:")

        assert_has(session, "#artist-search-input[value='status:']")
        assert_has(session, "[role='option']", text: "Active")
        assert_has(session, "[role='option']", text: "Inactive")
      end
    end

    describe "facet-value autocomplete (enum picklist)" do
      test "picking 'Active' completes the token and emits the parsed query + Ash filter", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:")

        session = click_button(session, "Active")

        assert_has(session, "#artist-search-input[value='status:active ']")
        assert_has(session, "#last-facets", text: "{:status, :eq, :active}")
        assert_has(session, "#last-filter", text: ~s(%{"status" => %{"eq" => :active}}))
      end
    end

    describe "unknown facet keys degrade to free text" do
      test "an unrecognised key never hard-errors, and lands in query.text as typed", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "bogus:active")

        assert_has(session, "#last-text", text: "bogus:active")
        assert_has(session, "#last-facets", text: "[]")
      end
    end

    describe "distinct-AND / repeated-OR, verified against the generated Ash filter" do
      test "distinct facet keys AND together", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:active genre:x")

        assert_has(session, "#last-filter", text: ~s("and" =>))
      end

      test "repeated instances of the same facet key OR together", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:active status:inactive")

        assert_has(session, "#last-filter", text: ~s("or" =>))
      end
    end

    describe "nested relationship-facet search is actor-scoped" do
      test "an actor who can read the related record sees it as a facet-value suggestion", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: "major"})
          |> type_search("artist-search-input", "genre:Major")

        assert_has(session, "[role='option']", text: "Major Pop")
      end

      test "an actor a policy hides the related record from never sees it as a suggestion", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "genre:Major")

        refute_has(session, "[role='option']", text: "Major Pop")
      end

      test "picking a nested-search suggestion inserts genre:<id>, displayed as the record's label", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "genre:Indie")

        session = click_button(session, "Indie Rock")

        assert_has(session, "#last-facets", text: ":genre, :eq")
        refute_has(session, "#artist-search-input[value='genre:Indie']")
      end
    end
  end
end
