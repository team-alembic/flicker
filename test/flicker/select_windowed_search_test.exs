defmodule Flicker.SelectWindowedSearchTest do
  @moduledoc """
  Windowed search / infinite scroll (Spec 010): the `paginate` attr, the
  `:offset` provider opt, the no-progress behavioural probe, `max_windows`,
  and the append announcements.

  `ArrowDown`-at-the-last-option and the `IntersectionObserver` sentinel are
  pure client-side JS (see the colocated hook in `Flicker.Components.Select`)
  — like the rest of the keyboard map, `PhoenixTest`/`Phoenix.LiveViewTest`
  can't run JavaScript, so they aren't exercised here. Both drive the exact
  same `"load-more"` server event this suite tests directly.
  """

  use Flicker.Test.ConnCase, async: true

  alias Phoenix.LiveViewTest

  require Phoenix.LiveViewTest

  # Records every `search/2` opts kwlist it's called with, to `opts[:recorder]`
  # (a test-process pid) — `start_async/3` runs the provider in a linked Task,
  # not the test process itself, so a bare `send(self(), ...)` inside
  # `search/2` wouldn't reach the assertions.
  defmodule RecordingProvider do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(query, opts) do
      send(Keyword.fetch!(opts, :recorder), {:search_opts, opts})
      Flicker.Providers.Static.search(query, opts)
    end

    @impl true
    def fetch(values, opts), do: Flicker.Providers.Static.fetch(values, opts)
  end

  defmodule SlowProvider do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(query, opts) do
      Process.sleep(30)
      Flicker.Providers.Static.search(query, opts)
    end

    @impl true
    def fetch(values, opts), do: Flicker.Providers.Static.fetch(values, opts)
  end

  # Both records (for `assert_received`) and sleeps a little (so a second
  # `load-more` fired immediately after the first is provably still racing
  # an in-flight window, not just fast enough to have already finished).
  defmodule RecordingSlowProvider do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(query, opts) do
      send(Keyword.fetch!(opts, :recorder), {:search_opts, opts})
      Process.sleep(30)
      Flicker.Providers.Static.search(query, opts)
    end

    @impl true
    def fetch(values, opts), do: Flicker.Providers.Static.fetch(values, opts)
  end

  # Combines `OffsetIgnoringProvider` and `RecordingProvider` — the
  # no-progress probe fixture, with visibility into exactly how many
  # `search/2` calls actually happened.
  defmodule RecordingOffsetIgnoringProvider do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(query, opts) do
      send(Keyword.fetch!(opts, :recorder), {:search_opts, opts})
      Flicker.Providers.Static.search(query, Keyword.delete(opts, :offset))
    end

    @impl true
    def fetch(values, opts), do: Flicker.Providers.Static.fetch(values, opts)
  end

  defp results(count), do: for(i <- 1..count, do: %Flicker.Result{value: i, label: "Item #{i}"})

  defp open(conn, session_overrides) do
    conn = Plug.Test.init_test_session(conn, Map.put(session_overrides, "mode", "controlled"))
    session = visit(conn, "/")

    session.view
    |> LiveViewTest.element("#picker-input")
    |> LiveViewTest.render_focus()

    LiveViewTest.render_async(session.view, 2_000)

    session
  end

  defp load_more(session) do
    session.view
    |> LiveViewTest.element("#picker")
    |> LiveViewTest.render_hook("load-more", %{})
  end

  describe "paginate: false (the default) — regression" do
    test "issues identical provider calls to the non-paginated path (no :offset opt)", %{conn: conn} do
      provider = {RecordingProvider, results: results(5), recorder: self()}
      conn |> open(%{"provider" => provider, "limit" => 3})

      assert_received {:search_opts, opts}
      refute Keyword.has_key?(opts, :offset)
    end

    test "renders no windowing markup (sentinel, loading-more row, aria-busy, data-paginate)", %{conn: conn} do
      session = open(conn, %{"provider" => {Flicker.Providers.Static, results: results(5)}, "limit" => 3})

      html = LiveViewTest.render(session.view)

      refute html =~ "data-flicker-sentinel"
      refute html =~ "data-paginate"
      refute html =~ "aria-busy"
      refute html =~ "Loading more..."
    end

    test "the narrow hint still shows when more results exist than the limit", %{conn: conn} do
      session = open(conn, %{"provider" => {Flicker.Providers.Static, results: results(5)}, "limit" => 3})

      assert_has(session, "li", text: "Keep typing to narrow results...")
    end
  end

  describe "paginate: true — appending windows" do
    test "reaching the tail appends the next window exactly once per load-more", %{conn: conn} do
      session =
        open(conn, %{"provider" => {Flicker.Providers.Static, results: results(6)}, "limit" => 3, "paginate" => true})

      assert_has(session, "[role='option']", count: 3)

      html = load_more(session)
      LiveViewTest.render_async(session.view, 2_000)

      assert_has(session, "[role='option']", count: 6)
      assert html =~ ~s(data-paginate="true")
    end

    test "a second load-more while one is already loading is ignored (debounced)", %{conn: conn} do
      provider = {RecordingSlowProvider, results: results(9), recorder: self()}
      session = open(conn, %{"provider" => provider, "limit" => 3, "paginate" => true})

      assert_received {:search_opts, _initial_call}

      load_more(session)
      load_more(session)
      LiveViewTest.render_async(session.view, 2_000)

      assert_received {:search_opts, _second_call}
      refute_received {:search_opts, _third_call}
    end

    test "a query keystroke mid-load discards the in-flight window and restarts at window 0", %{conn: conn} do
      session = open(conn, %{"provider" => {SlowProvider, results: results(9)}, "limit" => 3, "paginate" => true})

      load_more(session)

      session.view
      |> LiveViewTest.element("#picker-input")
      |> LiveViewTest.render_keyup(%{"value" => "item"})

      html = LiveViewTest.render_async(session.view, 2_000)

      assert_has(session, "[role='option']", count: 3)
      assert LiveViewTest.render(session.view) == html
    end

    test "resets to the top of the listbox on a new query", %{conn: conn} do
      session =
        open(conn, %{"provider" => {Flicker.Providers.Static, results: results(6)}, "limit" => 3, "paginate" => true})

      load_more(session)
      LiveViewTest.render_async(session.view, 2_000)

      session.view
      |> LiveViewTest.element("#picker-input")
      |> LiveViewTest.render_keyup(%{"value" => "item"})

      Phoenix.LiveViewTest.assert_push_event(session.view, "scrollListboxToTop", %{id: "picker-listbox"})
    end
  end

  describe "the no-progress behavioural probe" do
    test "a provider ignoring :offset gets exactly two windows requested, then the list is marked complete", %{
      conn: conn
    } do
      provider = {RecordingOffsetIgnoringProvider, results: results(9), recorder: self()}
      session = open(conn, %{"provider" => provider, "limit" => 3, "paginate" => true})

      assert_received {:search_opts, _first}

      load_more(session)
      LiveViewTest.render_async(session.view, 2_000)
      assert_received {:search_opts, _second}

      load_more(session)
      LiveViewTest.render_async(session.view, 2_000)
      refute_received {:search_opts, _third}

      # Still exactly window 0's results — the identical duplicate window
      # was discarded, not appended.
      assert_has(session, "[role='option']", count: 3)
      assert_has(session, "li", text: "Keep typing to narrow results...")
    end
  end

  describe "max_windows" do
    test "the tail renders the keep-typing hint once the cap is reached, with no load-more possible", %{conn: conn} do
      session =
        open(conn, %{
          "provider" => {Flicker.Providers.Static, results: results(9)},
          "limit" => 3,
          "paginate" => true,
          "max_windows" => 1
        })

      assert_has(session, "li", text: "Keep typing to narrow results...")
      refute LiveViewTest.render(session.view) =~ "data-flicker-sentinel"
    end
  end

  describe "aria-busy and the loading-more row" do
    test "aria-busy toggles around each window load, and a themed row shows while it loads", %{conn: conn} do
      session = open(conn, %{"provider" => {SlowProvider, results: results(6)}, "limit" => 3, "paginate" => true})

      assert LiveViewTest.render(session.view) =~ ~s(aria-busy="false")

      html = load_more(session)

      assert html =~ ~s(aria-busy="true")
      assert html =~ "Loading more..."

      html = LiveViewTest.render_async(session.view, 2_000)

      assert html =~ ~s(aria-busy="false")
      refute html =~ "Loading more..."
    end
  end

  describe "append announcements" do
    test "the live region announces the appended count and the new total, message-keyed", %{conn: conn} do
      session =
        open(conn, %{"provider" => {Flicker.Providers.Static, results: results(6)}, "limit" => 3, "paginate" => true})

      html = load_more(session)
      html = html <> LiveViewTest.render_async(session.view, 2_000)

      assert html =~ "3 more results, 6 total"
    end
  end

  describe "load-more with no paginate" do
    test "is a no-op", %{conn: conn} do
      session = open(conn, %{"provider" => {Flicker.Providers.Static, results: results(6)}, "limit" => 3})

      html = load_more(session)

      assert_has(session, "[role='option']", count: 3)
      refute html =~ "Loading more..."
    end
  end
end
