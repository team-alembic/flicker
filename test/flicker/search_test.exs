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

      test "picking a key suggestion opens that facet's editor", %{conn: conn} do
        # Spec 019 changed this deliberately: choosing `status:` opens the rich
        # editor instead of inserting text and waiting. It is the single biggest
        # discoverability win available — the user finds the control by doing
        # the thing they were already doing.
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "stat")

        session = click_button(session, "status:")

        assert_has(session, "#artist-search-input-facet-editor[role='dialog']")
        assert_has(session, "[role='option']", text: "Active")
        assert_has(session, "[role='option']", text: "Inactive")
      end

      test "typing the key by hand still works, with no editor opened", %{conn: conn} do
        # The editor is never the only way in (Spec 019): everything it can
        # express can still be typed.
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:")

        refute_has(session, "#artist-search-input-facet-editor")
        assert_has(session, "#artist-search-input[value='status:']")
        assert_has(session, "[role='option']", text: "Active")
      end
    end

    describe "facet-value autocomplete (enum picklist)" do
      test "picking 'Active' completes the token and emits the parsed query + Ash filter", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:")

        session = click_button(session, "Active")

        # Spec 012: the completed facet lifts out of the input into a pill and
        # the input clears — the emitted query + filter are unchanged.
        assert_has(session, "[role='listitem']", text: "Active")
        assert_has(session, "#artist-search-input[value='']")
        assert_has(session, "#last-facets", text: "{:status, :eq, :active}")
        assert_has(session, "#last-filter", text: ~s(%{"status" => %{"eq" => :active}}))
      end
    end

    describe "committed facet pills (Spec 012)" do
      test "completing a facet (trailing space) lifts it into a removable pill and clears the input", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:active ")

        # The token is gone from the input; it's now a pill, and the emitted
        # query still carries the facet.
        assert_has(session, "[role='listitem']", text: "Active")
        assert_has(session, "#artist-search-input[value='']")
        assert_has(session, "#last-facets", text: "{:status, :eq, :active}")

        # Removing the pill drops the facet from the emitted query.
        session.view
        |> Phoenix.LiveViewTest.element("button[aria-label='Remove Status Active']")
        |> Phoenix.LiveViewTest.render_click()

        assert_has(session, "#last-facets", text: "[]")
        refute_has(session, "[role='listitem']")
      end

      test "a facet value with a configured colour shows a colour dot on its pill (spec 017)", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:active ")

        assert_has(session, "[role='listitem'] span[style*='background-color:#16a34a']")
      end

      test "free text alongside a committed facet stays in the input", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "status:active rock ")

        assert_has(session, "[role='listitem']", text: "Active")
        assert_has(session, "#artist-search-input[value='rock']")
        assert_has(session, "#last-facets", text: "{:status, :eq, :active}")
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

    describe "keyup guard" do
      # A real browser fires `phx-keyup` for the Enter keydown the hook has
      # already turned into a suggestion-insert, and that trailing keyup's
      # "query" event would otherwise clobber the just-inserted token with
      # the pre-insert input value — see the guard clause in
      # `Flicker.Components.Search.handle_event("query", ...)`, caught by
      # the browser-driven suite (Spec 007).
      test "a query keyup for Enter/Escape/Tab never clobbers the inserted token", %{conn: conn} do
        session =
          conn
          |> visit_as(%{label: nil})
          |> type_search("artist-search-input", "stat")

        # A *value* insert rather than a key one: since Spec 019 a key
        # suggestion opens the editor instead of inserting, and what this test
        # is about is the trailing-keyup guard on the insert path itself.
        session.view
        |> Phoenix.LiveViewTest.element("#artist-search")
        |> Phoenix.LiveViewTest.render_hook("select_suggestion", %{"insert" => "status:active "})

        # The completed facet lifted into a pill and the buffer cleared.
        assert_has(session, "[role='listitem']", text: "Active")
        assert_has(session, "#artist-search-input[value='']")

        for key <- ["Enter", "Escape", "Tab"] do
          session.view
          |> Phoenix.LiveViewTest.element("#artist-search-input")
          |> Phoenix.LiveViewTest.render_keyup(%{"key" => key, "value" => "stat", "cursor" => "4"})

          # The stale pre-insert value must not resurrect itself, and the pill
          # must survive.
          assert_has(session, "#artist-search-input[value='']")
          assert_has(session, "[role='listitem']", text: "Active")
        end
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

    describe "facet-value autocomplete for a :boolean facet" do
      test "cursor at 'verified?:' suggests both true and false", %{conn: conn} do
        session = conn |> visit_as(%{label: nil}) |> type_search("artist-search-input", "verified?:")

        assert_has(session, "[role='option']", text: "true")
        assert_has(session, "[role='option']", text: "false")
      end

      test "prefix filtering: 'verified?:f' suggests only false", %{conn: conn} do
        session = conn |> visit_as(%{label: nil}) |> type_search("artist-search-input", "verified?:f")

        assert_has(session, "[role='option']", text: "false")
        refute_has(session, "[role='option']", text: "true")
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
