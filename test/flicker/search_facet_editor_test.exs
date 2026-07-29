if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchFacetEditorTest do
    @moduledoc """
    Spec 019's pop-out in `Flicker.search/1`: opening, the draft state, atomic
    commit, and cancel.

    The guarantee under test throughout is ADR-011's: nothing dispatches while
    an editor is open, and the commit is the one dispatch.
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

    defp open_status_editor(session) do
      session.view
      |> LiveViewTest.element("#artist-search")
      |> LiveViewTest.render_hook("select_suggestion", %{"insert" => "status:"})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    describe "opening" do
      test "choosing a facet key opens that facet's editor as a dialog" do
        session = visit_search() |> type("stat") |> open_status_editor()

        assert_has(session, "#artist-search-input-facet-editor[role='dialog']")
        assert_has(session, "#artist-search-input-facet-editor[aria-modal='true']")
      end

      test "the dialog is labelled by the facet" do
        session = visit_search() |> type("stat") |> open_status_editor()

        assert_has(session, "#artist-search-input-facet-editor[aria-label='Status']")
      end

      test "a boolean facet opens no pop-out — the switch is inline" do
        session = visit_search() |> type("verif")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("select_suggestion", %{"insert" => "verified?:"})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "#artist-search-input-facet-editor")
      end

      test "opening adds nothing to the query" do
        # Typing `stat` already dispatched (free text, correctly) — the point is
        # that *opening* the editor contributes no facet, so the emitted filter
        # is still empty. ADR-011: nothing dispatches from inside an open editor.
        session = visit_search() |> type("stat") |> open_status_editor()

        assert_has(session, "#last-filter", text: "%{}")
      end
    end

    describe "committing" do
      test "choosing a value commits once and closes the pop-out" do
        session = visit_search() |> type("stat") |> open_status_editor()

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("facet_editor_commit", %{"insert" => "status:active "})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "#artist-search-input-facet-editor")
        assert_has(session, "[role='listitem']", text: "Active")
        assert_has(session, "#last-filter")
      end

      test "the committed token is canonical, so it re-parses to a real facet" do
        session = visit_search() |> type("stat") |> open_status_editor()

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("facet_editor_commit", %{"insert" => "status:active "})

        LiveViewTest.render_async(session.view, 2_000)

        assert_has(session, "#last-filter", text: "status")
      end
    end

    describe "cancelling" do
      test "closes the pop-out and dispatches nothing" do
        session = visit_search() |> type("stat") |> open_status_editor()

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("facet_editor_cancel", %{})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "#artist-search-input-facet-editor")
        refute_has(session, "[role='listitem']")
      end
    end

    describe "the editor is never the only way in" do
      test "the same facet is still completable entirely by typing" do
        session = visit_search() |> type("status:active ")

        refute_has(session, "#artist-search-input-facet-editor")
        assert_has(session, "[role='listitem']", text: "Active")
      end
    end

    describe "at most one editor at a time" do
      test "opening a second closes the first" do
        session = visit_search() |> type("stat") |> open_status_editor()

        assert_has(session, "#artist-search-input-facet-editor[aria-label='Status']")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("select_suggestion", %{"insert" => "genre:"})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "#artist-search-input-facet-editor[aria-label='Status']")
      end
    end
  end
end
