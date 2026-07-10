if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchAnnouncementsTest do
    @moduledoc """
    Covers `Flicker.Components.Search`'s single live-region announcement
    (Spec 007): cursor-context changes (facet-key / facet-value / free-text)
    and their suggestion counts, all reachable through the same `query`
    event the JS keystroke handler pushes.
    """

    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers

    alias Phoenix.LiveViewTest

    @moduletag :ash

    defp visit_as(conn, actor) do
      conn = Plug.Test.init_test_session(conn, %{"actor" => actor})
      visit(conn, "/facet-search")
    end

    test "typing a facet key announces the facet-key context and matching-facet count", %{conn: conn} do
      session = conn |> visit_as(%{label: nil}) |> type_search("artist-search-input", "stat")

      assert_has(session, "#artist-search-announcer", text: "Typing a facet name")
      assert_has(session, "#artist-search-announcer", text: "1 matching facet")
    end

    test "typing a facet value announces the facet-value context, naming the facet, and match count", %{
      conn: conn
    } do
      session = conn |> visit_as(%{label: nil}) |> type_search("artist-search-input", "status:")

      assert_has(session, "#artist-search-announcer", text: "Typing a value for status")
      assert_has(session, "#artist-search-announcer", text: "2 matching values")
    end

    test "free text carries no suggestion-count announcement, only the free-text context", %{conn: conn} do
      session = conn |> visit_as(%{label: nil}) |> type_search("artist-search-input", "bogus:active")

      assert_has(session, "#artist-search-announcer", text: "Typing free text")
      refute_has(session, "#artist-search-announcer", text: "matching")
    end

    test "the related-search suggestion count reflects only the latest query", %{conn: conn} do
      session = conn |> visit_as(%{label: "major"})

      element = LiveViewTest.element(session.view, "#artist-search-input")
      LiveViewTest.render_keyup(element, %{"value" => "genre:M"})

      html = LiveViewTest.render_async(session.view)

      assert html =~ ~s(id="artist-search-announcer")
      assert html =~ "Typing a value for genre"
    end
  end
end
