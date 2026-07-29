defmodule Flicker.SelectDispatchPolicyTest do
  @moduledoc """
  `Flicker.select/1`'s `dispatch` attr ([Spec 020](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-020-query-dispatch-policy.md)):
  `:debounce` (the default, and today's behaviour) debounces typing,
  `:immediate` drops the debounce entirely, and `:enter` doesn't search on
  typing at all.

  `Flicker.Dispatch`'s own decisions are unit-tested in
  `Flicker.DispatchTest` — these tests only cover the wiring: that the policy
  reaches the rendered input, and that a held query leaves prior results
  standing rather than blanking the listbox.
  """

  use Flicker.Test.ConnCase, async: true

  alias Phoenix.LiveViewTest

  defp visit_with(conn, session) do
    conn |> Plug.Test.init_test_session(Map.merge(%{"mode" => "controlled"}, session)) |> visit("/")
  end

  defp type(session, text) do
    session.view
    |> LiveViewTest.element("#picker-input")
    |> LiveViewTest.render_keyup(%{"value" => text})

    LiveViewTest.render_async(session.view, 2_000)
    session
  end

  describe ":debounce (default)" do
    test "keeps today's behaviour — the input still carries phx-debounce", %{conn: conn} do
      session = visit_with(conn, %{})

      assert_has(session, "#picker-input[phx-debounce='150']")
    end

    test "searches on typing", %{conn: conn} do
      session = conn |> visit_with(%{}) |> type("casey")

      assert_has(session, "li", text: "Casey Cassidy")
    end
  end

  describe ":immediate" do
    test "omits phx-debounce entirely", %{conn: conn} do
      session = visit_with(conn, %{"dispatch" => :immediate})

      refute_has(session, "#picker-input[phx-debounce]")
    end

    test "still searches on typing", %{conn: conn} do
      session = conn |> visit_with(%{"dispatch" => :immediate}) |> type("casey")

      assert_has(session, "li", text: "Casey Cassidy")
    end
  end

  describe ":enter" do
    test "omits phx-debounce entirely", %{conn: conn} do
      session = visit_with(conn, %{"dispatch" => :enter})

      refute_has(session, "#picker-input[phx-debounce]")
    end

    test "does not search while typing", %{conn: conn} do
      session = conn |> visit_with(%{"dispatch" => :enter}) |> type("casey")

      refute_has(session, "li", text: "Casey Cassidy")
    end

    test "typing a query that matches nothing leaves earlier results standing" do
      # The listbox must not blank itself while a query is held: opening runs
      # the initial listing (which always dispatches, under every policy), and
      # typing afterwards holds — so the listing stays on screen rather than
      # collapsing to an empty list.
      conn = Plug.Test.init_test_session(build_conn(), %{"mode" => "controlled", "dispatch" => :enter})
      session = visit(conn, "/")

      session.view |> LiveViewTest.element("#picker-input") |> LiveViewTest.render_focus()
      LiveViewTest.render_async(session.view, 2_000)

      assert_has(session, "li", text: "Casey Cassidy")

      type(session, "zzzzz")

      assert_has(session, "li", text: "Casey Cassidy")
      refute_has(session, "li", text: "No results")
    end
  end

  describe ":enter — Enter dispatches" do
    test "pressing Enter searches the held text", %{conn: conn} do
      session = conn |> visit_with(%{"dispatch" => :enter}) |> type("casey")

      refute_has(session, "li", text: "Casey Cassidy")

      session.view
      |> LiveViewTest.element("#picker")
      |> LiveViewTest.render_hook("dispatch_query", %{"value" => "casey"})

      LiveViewTest.render_async(session.view, 2_000)

      assert_has(session, "li", text: "Casey Cassidy")
    end

    test "the hint shows while text is held and clears once dispatched", %{conn: conn} do
      session = conn |> visit_with(%{"dispatch" => :enter}) |> type("casey")

      assert_has(session, "#picker-input-dispatch-hint", text: "Press Enter to search")
      assert_has(session, "#picker-input[aria-describedby='picker-input-dispatch-hint']")

      session.view
      |> LiveViewTest.element("#picker")
      |> LiveViewTest.render_hook("dispatch_query", %{"value" => "casey"})

      LiveViewTest.render_async(session.view, 2_000)

      refute_has(session, "#picker-input-dispatch-hint")
      refute_has(session, "#picker-input[aria-describedby]")
    end

    test "the hook is told the policy, so Enter only dispatches under :enter", %{conn: conn} do
      assert_has(visit_with(conn, %{"dispatch" => :enter}), "#picker[data-dispatch='enter']")
      assert_has(visit_with(conn, %{}), "#picker[data-dispatch='debounce']")
      assert_has(visit_with(conn, %{"dispatch" => :immediate}), "#picker[data-dispatch='immediate']")
    end
  end

  describe "the dispatch hint" do
    test "never shows under the dispatching policies", %{conn: conn} do
      for policy <- [:debounce, :immediate] do
        session = conn |> visit_with(%{"dispatch" => policy}) |> type("casey")

        refute_has(session, "#picker-input-dispatch-hint")
      end
    end
  end

  describe "the initial listing" do
    test "dispatches under every policy, including :enter" do
      for policy <- Flicker.Dispatch.policies() do
        conn = Plug.Test.init_test_session(build_conn(), %{"mode" => "controlled", "dispatch" => policy})
        session = visit(conn, "/")

        session.view |> LiveViewTest.element("#picker-input") |> LiveViewTest.render_focus()
        LiveViewTest.render_async(session.view, 2_000)

        assert_has(session, "li", text: "Casey Cassidy")
      end
    end
  end
end
