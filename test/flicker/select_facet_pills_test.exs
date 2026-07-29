if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SelectFacetPillsTest do
    @moduledoc """
    Spec 015: facets inside `Flicker.select/1`. The distinction under test is
    that a facet pill *scopes the search* while a chip *is a selection* — they
    coexist and are not the same thing.
    """

    use Flicker.Test.ConnCase, async: false

    alias Phoenix.LiveViewTest

    defp visit_select(session \\ %{}) do
      build_conn()
      |> Plug.Test.init_test_session(Map.merge(%{"actor" => %{label: nil}}, session))
      |> visit("/facet-select")
    end

    defp type(session, text) do
      session.view
      |> LiveViewTest.element("#artist-picker-input")
      |> LiveViewTest.render_keyup(%{"value" => text})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    describe "a committed facet becomes a pill" do
      test "the terminated token leaves the input and renders as a pill" do
        session = visit_select() |> type("status:active ")

        assert_has(session, "[role='listitem']", text: "Active")
        assert_has(session, "#artist-picker-input[value='']")
      end

      test "the pill shows its field label" do
        session = visit_select() |> type("status:active ")

        assert_has(session, "[role='listitem']", text: "Status")
      end

      test "the pill row is labelled as filters, not as a selection" do
        session = visit_select() |> type("status:active ")

        assert_has(session, "[aria-label='Active filters']")
      end
    end

    describe "the in-progress token stays put" do
      test "an unterminated token remains in the buffer for autocomplete" do
        session = visit_select() |> type("status:activ")

        assert_has(session, "#artist-picker-input[value='status:activ']")
        refute_has(session, "[role='listitem']")
      end

      test "free text alongside a committed facet stays in the buffer" do
        session = visit_select() |> type("status:active Riley")

        assert_has(session, "[role='listitem']", text: "Active")
        assert_has(session, "#artist-picker-input[value='Riley']")
      end
    end

    describe "facets scope the search without touching the selection" do
      test "a facet narrows which records are offered" do
        session = visit_select() |> type("status:active ")

        # Every offered record must satisfy the committed facet.
        refute_has(session, "[role='option']", text: "Casey Cassidy")
      end

      test "removing a pill re-runs the search without it" do
        session = visit_select() |> type("status:active ")

        assert_has(session, "[role='listitem']", text: "Active")

        session.view
        |> LiveViewTest.element("#artist-picker")
        |> LiveViewTest.render_hook("remove_facet", %{"index" => "0"})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "[role='listitem']")
      end

      test "committing a facet does not select a record" do
        session = visit_select() |> type("status:active ")

        refute_has(session, "#selection")
      end
    end

    describe "no facets configured" do
      test "behaviour is unchanged — no pill row at all" do
        session =
          build_conn()
          |> Plug.Test.init_test_session(%{"mode" => "controlled"})
          |> visit("/")

        session.view
        |> LiveViewTest.element("#picker-input")
        |> LiveViewTest.render_keyup(%{"value" => "status:active "})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "[aria-label='Active filters']")
        assert_has(session, "#picker-input[value='status:active ']")
      end
    end
  end
end
