if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchFacetPillsTest do
    @moduledoc """
    Spec 012's remaining criteria: the pill's field label (no colon), and Spec
    019's pill re-edit built on top of it.
    """

    use Flicker.Test.ConnCase, async: false

    alias Phoenix.LiveViewTest

    defp visit_search do
      build_conn() |> Plug.Test.init_test_session(%{}) |> visit("/facet-search")
    end

    defp type(session, text) do
      session.view
      |> LiveViewTest.element("#artist-search-input")
      |> LiveViewTest.render_keyup(%{"value" => text})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    describe "the pill shows its field label" do
      test "a committed facet renders both the field and the value, with no colon" do
        session = visit_search() |> type("status:active ")

        assert_has(session, "[role='listitem']", text: "Status")
        assert_has(session, "[role='listitem']", text: "Active")

        # No colon in the *visible* text. The `title` attribute still reads
        # "Status: Active" — that's a tooltip, and a colon belongs there.
        visible =
          session.view
          |> LiveViewTest.render()
          |> String.replace(~r/<[^>]*>/, " ")

        refute visible =~ "Status:"
        assert visible =~ "Status"
        assert visible =~ "Active"
      end

      test "the value keeps its display label, not the raw atom" do
        session = visit_search() |> type("status:active ")

        html = LiveViewTest.render(session.view)

        assert html =~ "Active"
      end

      test "the token leaves the input once committed" do
        session = visit_search() |> type("status:active ")

        assert_has(session, "#artist-search-input[value='']")
      end
    end

    describe "the pill row is labelled as filters" do
      test "not as 'Selected items', which is what a selection chip row is" do
        # Found by reading the accessibility tree: a screen reader user hearing
        # "Selected items" for a row of *filters* is told the wrong thing about
        # what they do.
        session = visit_search() |> type("status:active ")

        assert_has(session, "[role='list'][aria-label='Active filters']")
        refute_has(session, "[role='list'][aria-label='Selected items']")
      end
    end

    describe "pill re-edit (Spec 019)" do
      test "a facet with an editor exposes a control to reopen it" do
        session = visit_search() |> type("status:active ")

        assert_has(session, "[aria-label='Edit Status']")
      end

      test "clicking it reopens the editor pre-filled" do
        session = visit_search() |> type("status:active ")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("facet_editor_reopen", %{"index" => "0"})

        LiveViewTest.render_async(session.view, 2_000)

        assert_has(session, "#artist-search-input-facet-editor[role='dialog']")
        assert_has(session, "#artist-search-input-facet-editor[aria-label='Status']")
      end

      test "reopening dispatches nothing on its own" do
        session = visit_search() |> type("status:active ")

        html_before = LiveViewTest.render(session.view)

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("facet_editor_reopen", %{"index" => "0"})

        LiveViewTest.render_async(session.view, 2_000)

        # The committed pill is untouched — reopening is not a change.
        assert_has(session, "[role='listitem']", text: "Active")
        assert html_before =~ "Active"
      end

      test "an out-of-range index is ignored rather than crashing" do
        session = visit_search() |> type("status:active ")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("facet_editor_reopen", %{"index" => "99"})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "#artist-search-input-facet-editor")
      end
    end

    describe "removal still works" do
      test "removing a pill drops it from the query" do
        session = visit_search() |> type("status:active ")

        assert_has(session, "[role='listitem']", text: "Active")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("remove_facet", %{"index" => "0"})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "[role='listitem']")
      end
    end
  end
end
