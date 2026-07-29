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

  defmodule SlowProvider do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(%Flicker.Query{text: "slow"}, _opts) do
      Process.sleep(300)
      {:ok, [%Flicker.Result{value: "9", label: "Slow result"}]}
    end

    def search(_query, _opts), do: {:ok, [%Flicker.Result{value: "1", label: "Casey Cassidy"}]}

    @impl true
    def fetch(_values, _opts), do: {:ok, []}
  end

  describe "stale results" do
    test "the previous results stay rendered, marked stale, while the next search runs" do
      conn = Plug.Test.init_test_session(build_conn(), %{"mode" => "controlled", "provider" => SlowProvider})
      session = visit(conn, "/")

      session.view |> LiveViewTest.element("#picker-input") |> LiveViewTest.render_focus()
      LiveViewTest.render_async(session.view, 2_000)

      assert_has(session, "li", text: "Casey Cassidy")

      # Typing kicks off the slow search without awaiting it: the earlier
      # results must still be on screen, and the listbox marked stale.
      session.view
      |> LiveViewTest.element("#picker-input")
      |> LiveViewTest.render_keyup(%{"value" => "slow"})

      html = LiveViewTest.render(session.view)

      assert html =~ "Casey Cassidy"
      assert html =~ "flicker-results-stale"

      LiveViewTest.render_async(session.view, 2_000)

      html = LiveViewTest.render(session.view)

      assert html =~ "Slow result"
      refute html =~ "flicker-results-stale"
    end
  end

  describe "loading_delay" do
    test "the loading row renders hidden, for the hook to reveal", %{conn: conn} do
      # The delay has to be client-side: Process.send_after/3 from a
      # LiveComponent lands in the host LiveView, which has no clause for it.
      # So the server renders the row hidden and marked, and the hook reveals it
      # only if the request is still in flight when the timer fires.
      session = visit_with(conn, %{"provider" => SlowProvider})

      session.view
      |> LiveViewTest.element("#picker-input")
      |> LiveViewTest.render_keyup(%{"value" => "slow"})

      html = LiveViewTest.render(session.view)

      assert html =~ "data-flicker-loading"
      assert html =~ "visibility:hidden"
    end

    test "the delay reaches the hook as a data attribute", %{conn: conn} do
      assert_has(visit_with(conn, %{}), "#picker[data-loading-delay='200']")
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
