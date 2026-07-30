if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchFacetTriggerTest do
    @moduledoc """
    Spec 024 in a live `Flicker.search/1`: the trigger gates the facet menu, the
    editor opens on a pick, the hint is announced, and none of it reaches the
    query the host receives.
    """

    use Flicker.Test.ConnCase, async: false

    alias Phoenix.LiveViewTest

    defp visit_search(session_data \\ %{}) do
      build_conn() |> Plug.Test.init_test_session(session_data) |> visit("/facet-search")
    end

    defp with_trigger(trigger \\ "@", extra \\ %{}) do
      visit_search(Map.merge(%{"facet_trigger" => trigger}, extra))
    end

    defp type(session, text) do
      session.view
      |> LiveViewTest.element("#artist-search-input")
      |> LiveViewTest.render_keyup(%{"value" => text})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    # Only the suggestion listbox. Asserting against the whole render would
    # match the placeholder's own "try status:active" example text.
    defp listbox(session) do
      case Regex.run(~r{<ul [^>]*role="listbox".*?</ul>}s, LiveViewTest.render(session.view)) do
        [html] -> html
        nil -> ""
      end
    end

    describe "the trigger gates the facet menu" do
      test "a bare word offers no facet keys" do
        session = with_trigger() |> type("stat")

        refute listbox(session) =~ "status:"
      end

      test "the same word does offer them with no trigger configured" do
        session = visit_search() |> type("stat")

        assert listbox(session) =~ "status:"
      end

      test "a triggered token opens the menu" do
        session = with_trigger() |> type("@stat")

        assert listbox(session) =~ "status:"
      end

      test "a bare trigger offers every facet" do
        session = with_trigger() |> type("@")

        html = listbox(session)

        assert html =~ "status:"
        assert html =~ "genre:"
      end

      test "the listbox reports itself expanded only for a triggered token" do
        with_trigger() |> type("@stat") |> assert_has("#artist-search-input[aria-expanded='true']")
        with_trigger() |> type("stat") |> assert_has("#artist-search-input[aria-expanded='false']")
      end
    end

    describe "scoped triggers" do
      test "each trigger offers only its own facets" do
        session = with_trigger(%{"@" => [:status], "#" => [:genre]})

        html = session |> type("@") |> listbox()
        assert html =~ "status:"
        refute html =~ "genre:"

        html = session |> type("#") |> listbox()
        assert html =~ "genre:"
        refute html =~ "status:"
      end

      test "a facet outside every trigger's scope is still recognised when typed out" do
        session = with_trigger(%{"@" => [:status]}) |> type("genre:rock ")

        assert_has(session, "#last-facets", text: ":genre")
      end
    end

    describe "the trigger never reaches the query" do
      test "picking a key completes to the canonical token" do
        # `open_editor_on_pick: false` so the pick's effect on the *input* is
        # what's observable — with the editor open, the token isn't spliced until
        # the editor commits (ADR-011).
        session = with_trigger("@", %{"open_editor_on_pick" => false}) |> type("@gen")

        session.view
        |> LiveViewTest.element("[role='option']", "genre:")
        |> LiveViewTest.render_click()

        assert_has(session, "#artist-search-input[value='genre:']")
      end

      test "a committed facet reaches the host with no trigger in it" do
        session = with_trigger("@", %{"open_editor_on_pick" => false}) |> type("@gen")

        session.view
        |> LiveViewTest.element("[role='option']", "genre:")
        |> LiveViewTest.render_click()

        session = type(session, "genre:rock ")

        assert_has(session, "#last-facets", text: ":genre")
        refute LiveViewTest.render(session.view) =~ "@genre"
      end

      test "a literal trigger the user meant as text becomes free text" do
        session = with_trigger() |> type("@nope ")

        assert_has(session, "#last-text", text: "@nope")
      end

      test "an email address is free text, not a facet attempt" do
        session = with_trigger() |> type("casey@example.com ")

        assert_has(session, "#last-text", text: "casey@example.com")
      end

      test "a facet typed out in full still filters" do
        # The pasted/URL-restored case. If a trigger broke this, every shared
        # search link would silently stop filtering.
        session = with_trigger() |> type("status:active ")

        assert_has(session, "#last-facets", text: ":status")
      end
    end

    describe "the editor opens on a pick" do
      test "picking a facet with an editor opens its pop-out" do
        session = with_trigger() |> type("@status")

        session.view
        |> LiveViewTest.element("[role='option']", "status:")
        |> LiveViewTest.render_click()

        assert_has(session, "[role='dialog'][aria-modal='true']")
      end

      test "open_editor_on_pick: false leaves the user in value position instead" do
        session = with_trigger("@", %{"open_editor_on_pick" => false}) |> type("@status")

        session.view
        |> LiveViewTest.element("[role='option']", "status:")
        |> LiveViewTest.render_click()

        refute_has(session, "[role='dialog'][aria-modal='true']")
        assert_has(session, "#artist-search-input[value='status:']")
      end

      test "cancelling the editor restores the typed text exactly, trigger and all" do
        session = with_trigger() |> type("@status")

        session.view
        |> LiveViewTest.element("[role='option']", "status:")
        |> LiveViewTest.render_click()

        session.view
        |> LiveViewTest.element("[data-flicker-editor-close]")
        |> LiveViewTest.render_click()

        # ADR-011: cancel discards the draft and changes nothing about the
        # query — including the input buffer, which is still what the user typed.
        refute_has(session, "[role='dialog'][aria-modal='true']")
        assert_has(session, "#artist-search-input[value='@status']")
      end
    end

    describe "discoverability" do
      test "the hint names the trigger and is referenced by the input" do
        session = with_trigger()

        assert_has(session, "#artist-search-input-trigger-hint", text: "Type @ to filter")

        assert_has(
          session,
          "#artist-search-input[aria-describedby~='artist-search-input-trigger-hint']"
        )
      end

      test "multiple triggers are conjoined" do
        session = with_trigger(%{"@" => [:status], "#" => [:genre]})

        assert_has(session, "#artist-search-input-trigger-hint", text: "#")
        assert_has(session, "#artist-search-input-trigger-hint", text: "@")
      end

      test "no hint without a trigger, where the key list is its own discovery" do
        refute_has(visit_search(), "#artist-search-input-trigger-hint")
      end

      test "the placeholder teaches the trigger, not the colon form" do
        assert_has(with_trigger(), "#artist-search-input[placeholder='Filter... (try @status)']")
        assert_has(visit_search(), "#artist-search-input[placeholder='Filter... (try status:active)']")
      end

      test "the hint stays put as the user types" do
        # It is an `aria-describedby` target; a description that comes and goes
        # is one a screen reader user can't rely on hearing.
        session = with_trigger() |> type("something")

        assert_has(session, "#artist-search-input-trigger-hint")
      end
    end

    describe "announcements" do
      test "a triggered token announces facet-key context" do
        session = with_trigger() |> type("@stat")

        assert_has(session, "#artist-search-announcer", text: "Typing a facet name")
      end

      test "a bare word announces free text" do
        session = with_trigger() |> type("stat")

        assert_has(session, "#artist-search-announcer", text: "Typing free text")
      end
    end
  end
end
