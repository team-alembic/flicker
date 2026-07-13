defmodule Flicker.SelectAnnouncementsTest do
  @moduledoc """
  Covers `Flicker.Components.Select`'s single live-region announcement
  (Spec 007) across every reachable state transition in the Spec 001
  keyboard map: opening, searching, empty results, loading, selecting,
  closing, clearing, chip removal, `max_selections`, and stale-result
  cancellation extending to the announcement text itself.

  Arrow-key/`Enter` highlight movement is client-side JS not exercised by
  PhoenixTest (see `Flicker.SelectKeyboardTest`'s moduledoc) — the
  transitions here are the server-reachable ones: `focus`, `query`,
  `select`, `escape`, `close`, `clear`, `remove_chip`, `remove_last_chip`.
  """

  use Flicker.Test.ConnCase, async: true

  import Flicker.Test.Helpers

  alias Phoenix.LiveViewTest

  defp visit_mode(conn, session_overrides) do
    conn = Plug.Test.init_test_session(conn, session_overrides)
    visit(conn, "/")
  end

  defp visit_multi(conn, session_overrides) do
    conn = Plug.Test.init_test_session(conn, session_overrides)
    visit(conn, "/multi")
  end

  describe "result counts" do
    test "opening with no query announces the full result count", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "controlled"})

      session.view
      |> LiveViewTest.element("#picker")
      |> LiveViewTest.render_hook("focus", %{})

      html = LiveViewTest.render_async(session.view, 2_000)

      assert html =~ ~s(id="picker-announcer")
      assert html =~ "3 results available"
    end

    test "typing narrows the announced count to the matching results", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      assert_has(session, "#picker-announcer", text: "1 result available")
    end

    test "a query with no matches announces zero results, not silence", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "zzz-no-match")

      assert_has(session, "#picker-announcer", text: "No results available")
    end
  end

  describe "loading" do
    defmodule SlowProvider do
      @moduledoc false
      @behaviour Flicker.Provider

      @impl true
      def search(%Flicker.Query{}, _opts) do
        Process.sleep(50)
        {:ok, [%Flicker.Result{value: "1", label: "Slow Result"}]}
      end

      @impl true
      def fetch(_values, _opts), do: {:ok, []}
    end

    test "the announcement reads 'Loading...' while a search is in flight", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{"mode" => "controlled", "provider" => SlowProvider})
      session = visit(conn, "/")

      html =
        session.view
        |> LiveViewTest.element("#picker-input")
        |> LiveViewTest.render_keyup(%{"value" => "anything"})

      assert html =~ ~s(id="picker-announcer")
      assert html =~ "Loading..."
    end
  end

  describe "selection made" do
    test "selecting a result announces the selected item by name", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")

      assert_has(session, "#picker-announcer", text: "Casey Cassidy selected")
    end

    test "clearing the selection stops announcing it", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")
      assert_has(session, "#picker-announcer", text: "Casey Cassidy selected")

      html =
        session.view
        |> LiveViewTest.element("#picker")
        |> LiveViewTest.render_hook("clear", %{})

      refute html =~ "Casey Cassidy selected"
    end
  end

  describe "escape/close transitions" do
    test "escape closing the listbox stops announcing a result count", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      assert_has(session, "#picker-announcer", text: "1 result available")

      html =
        session.view
        |> LiveViewTest.element("#picker")
        |> LiveViewTest.render_hook("escape", %{})

      refute html =~ "1 result available"
    end

    test "click-away close stops announcing a result count", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      assert_has(session, "#picker-announcer", text: "1 result available")

      html =
        session.view
        |> LiveViewTest.element("#picker")
        |> LiveViewTest.render_hook("close", %{})

      refute html =~ "1 result available"
    end
  end

  describe "multi-select: chip added/removed and max_selections" do
    test "adding a chip announces the new selected count", %{conn: conn} do
      session =
        conn
        |> visit_multi(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")

      assert_has(session, "#picker-announcer", text: "1 item selected")
    end

    test "removing a chip announces the decreased selected count", %{conn: conn} do
      session =
        conn
        |> visit_multi(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")
      assert_has(session, "#picker-announcer", text: "1 item selected")

      session.view
      |> LiveViewTest.element("button[aria-label='Remove Casey Cassidy']")
      |> LiveViewTest.render_click()

      assert_has(session, "#picker-announcer", text: "No items selected")
    end

    test "backspace-removal (remove_last_chip) also announces the decreased count", %{conn: conn} do
      session =
        conn
        |> visit_multi(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")

      html =
        session.view
        |> LiveViewTest.element("#picker")
        |> LiveViewTest.render_hook("remove_last_chip", %{})

      assert html =~ "No items selected"
    end

    test "reaching max_selections is announced alongside the open listbox's count", %{conn: conn} do
      session =
        conn
        |> visit_multi(%{"mode" => "controlled", "max_selections" => 1})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")
      session = type_search(session, "picker-input", "riv")

      assert_has(session, "#picker-announcer", text: "Maximum of 1 selections reached")
    end
  end

  describe "stale-result cancellation extends to announcements" do
    defmodule SlowThenFastProvider do
      @moduledoc false
      @behaviour Flicker.Provider

      @impl true
      def search(%Flicker.Query{text: "slow"}, _opts) do
        Process.sleep(200)
        {:ok, [%Flicker.Result{value: "1", label: "Stale"}, %Flicker.Result{value: "2", label: "Stale two"}]}
      end

      def search(%Flicker.Query{text: "fast"}, _opts), do: {:ok, [%Flicker.Result{value: "3", label: "Fresh"}]}
      def search(_query, _opts), do: {:ok, []}

      @impl true
      def fetch(_values, _opts), do: {:ok, []}
    end

    test "the announced count reflects only the latest query, never a slower stale one", %{conn: conn} do
      conn =
        Plug.Test.init_test_session(conn, %{"mode" => "controlled", "provider" => SlowThenFastProvider})

      session = visit(conn, "/")

      element = LiveViewTest.element(session.view, "#picker-input")
      LiveViewTest.render_keyup(element, %{"value" => "slow"})
      LiveViewTest.render_keyup(element, %{"value" => "fast"})

      html = LiveViewTest.render_async(session.view, 2_000)

      assert html =~ "1 result available"
      refute html =~ "2 results available"
    end
  end

  describe "facet cursor-context changes" do
    @describetag :ash

    if Code.ensure_loaded?(Ash) do
      defp visit_facet(conn, actor) do
        conn = Plug.Test.init_test_session(conn, %{"actor" => actor})
        visit(conn, "/facet-select")
      end

      test "typing a facet key announces the facet-key context", %{conn: conn} do
        session = conn |> visit_facet(%{label: nil}) |> type_search("artist-picker-input", "stat")

        assert_has(session, "#artist-picker-announcer", text: "Typing a facet name")
      end

      test "typing a facet value announces the facet-value context, naming the facet", %{conn: conn} do
        session = conn |> visit_facet(%{label: nil}) |> type_search("artist-picker-input", "status:")

        assert_has(session, "#artist-picker-announcer", text: "Typing a value for status")
      end
    end
  end
end
