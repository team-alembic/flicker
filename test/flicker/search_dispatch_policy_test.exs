if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchDispatchPolicyTest do
    @moduledoc """
    `Flicker.search/1`'s `dispatch` attr ([Spec 020](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-020-query-dispatch-policy.md)).

    This component owns no provider — the host notification *is* the dispatch
    — so the policy gates `on_change`. What matters here is that a facet
    commit still reaches the host under `:enter`, since a policy governs
    free-text typing and nothing else.
    """

    use Flicker.Test.ConnCase, async: false

    alias Phoenix.LiveViewTest

    defp visit_with(conn, session) do
      conn |> Plug.Test.init_test_session(session) |> visit("/facet-search")
    end

    defp type(session, text) do
      session.view
      |> LiveViewTest.element("#artist-search-input")
      |> LiveViewTest.render_keyup(%{"value" => text})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    describe ":debounce (default)" do
      test "keeps today's behaviour: phx-debounce present, typing emits on_change", %{conn: conn} do
        session = visit_with(conn, %{})

        assert_has(session, "#artist-search-input[phx-debounce='150']")

        session = type(session, "nirvana")

        assert_has(session, "#last-text", text: "nirvana")
      end
    end

    describe ":immediate" do
      test "omits phx-debounce and still emits on typing", %{conn: conn} do
        session = visit_with(conn, %{"dispatch" => :immediate})

        refute_has(session, "#artist-search-input[phx-debounce]")

        session = type(session, "nirvana")

        assert_has(session, "#last-text", text: "nirvana")
      end
    end

    describe ":enter" do
      test "typing does not emit on_change", %{conn: conn} do
        session = conn |> visit_with(%{"dispatch" => :enter}) |> type("nirvana")

        refute_has(session, "#last-text")
      end

      test "Enter releases the held text to the host", %{conn: conn} do
        session = conn |> visit_with(%{"dispatch" => :enter}) |> type("nirvana")

        refute_has(session, "#last-text")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("dispatch_query", %{})

        LiveViewTest.render_async(session.view, 2_000)

        assert_has(session, "#last-text", text: "nirvana")
      end

      test "the hint shows while text is held, and is referenced by aria-describedby", %{conn: conn} do
        session = conn |> visit_with(%{"dispatch" => :enter}) |> type("nirvana")

        assert_has(session, "#artist-search-input-dispatch-hint", text: "Press Enter to search")

        assert_has(
          session,
          "#artist-search-input[aria-describedby='artist-search-input-dispatch-hint']"
        )
      end

      test "committing a facet still emits, since a policy only governs free text", %{conn: conn} do
        # A facet commit is a deliberate discrete act (ADR-011), so it
        # dispatches under every policy — otherwise choosing `status:active`
        # would silently do nothing until Enter.
        session = conn |> visit_with(%{"dispatch" => :enter}) |> type("status:")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("select_suggestion", %{"insert" => "status:active "})

        LiveViewTest.render_async(session.view, 2_000)

        assert_has(session, "#last-filter")
      end
    end
  end
end
