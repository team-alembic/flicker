defmodule Flicker.SelectMultiTest do
  @moduledoc """
  Multi-select acceptance criteria (Spec 002) against
  `Flicker.Test.MultiHostLive`, mirroring `Flicker.SelectTest`'s single-select
  coverage.
  """

  use Flicker.Test.ConnCase, async: true

  import Flicker.Test.Helpers
  import Phoenix.LiveViewTest, only: [live_isolated: 3]

  alias Phoenix.LiveViewTest

  defmodule CountingProvider do
    @moduledoc """
    Wraps a fixed result set, recording every `fetch/2` call's argument list
    via an `Agent` passed in `opts[:counter]` — proves label resolution
    always goes out in one batched call carrying every value, never one
    call per value (ADR-003).
    """

    @behaviour Flicker.Provider

    alias Flicker.{Query, Result}

    @results [
      %Result{value: "1", label: "Casey Cassidy", sublabel: "Bass"},
      %Result{value: "2", label: "Alex Rivers", sublabel: "Drums"},
      %Result{value: "3", label: "Jordan Blake", sublabel: "Vocals"}
    ]

    @impl true
    def search(%Query{text: text}, _opts) do
      {:ok, Enum.filter(@results, &String.contains?(String.downcase(&1.label), String.downcase(text)))}
    end

    @impl true
    def fetch(values, opts) do
      Agent.update(Keyword.fetch!(opts, :counter), &[values | &1])
      {:ok, Enum.filter(@results, &(&1.value in values))}
    end
  end

  defp visit_mode(conn, session_overrides) do
    conn = Plug.Test.init_test_session(conn, session_overrides)
    visit(conn, "/multi")
  end

  describe "batch label resolution" do
    test "an edit form opening with three ids set shows three labelled chips after exactly one fetch/2 call", %{
      conn: conn
    } do
      {:ok, counter} = Agent.start_link(fn -> [] end)

      session = %{
        "mode" => "form",
        "provider" => {CountingProvider, counter: counter},
        "initial_values" => ["1", "2", "3"]
      }

      # A LiveView mount is a dead render followed by a connected render
      # (ADR-005's dead-render gating) — both call `update/2`, so both
      # resolve the selection, but each does so in a single batched call:
      # never one `fetch/2` call per value (ADR-003's N+1 the spec rules
      # out), always one call carrying every value.
      {:ok, _view, html} = live_isolated(conn, Flicker.Test.MultiHostLive, session: session)

      calls = Agent.get(counter, & &1)
      assert calls != []
      assert Enum.all?(calls, &(length(&1) == 3))
      assert html =~ "Casey Cassidy"
      assert html =~ "Alex Rivers"
      assert html =~ "Jordan Blake"
    end

    test "values deleted/policy-hidden since selection are dropped gracefully (partial fetch results)", %{
      conn: conn
    } do
      {:ok, counter} = Agent.start_link(fn -> [] end)

      session = %{
        "mode" => "form",
        "provider" => {CountingProvider, counter: counter},
        "initial_values" => ["1", "missing", "3"]
      }

      {:ok, _view, html} = live_isolated(conn, Flicker.Test.MultiHostLive, session: session)

      calls = Agent.get(counter, & &1)
      assert calls != []
      assert Enum.all?(calls, &(length(&1) == 3))
      assert html =~ "Casey Cassidy"
      assert html =~ "Jordan Blake"
      refute html =~ "missing"
    end
  end

  describe "form-field mode" do
    test "submitting the form yields array params with no host-side transformation", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "form"})
        |> type_search("picker-input", "cas")

      session =
        session
        |> click_button("Casey Cassidy")
        |> type_search("picker-input", "riv")

      session = session |> click_button("Alex Rivers") |> click_button("Submit")

      assert_has(session, "#submitted", text: ~s("worker_ids" => ["1", "2"]))
    end

    test "the _unused_ recovery marker holds for array inputs when nothing is selected yet", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "form"})

      html = LiveViewTest.render(session.view)
      assert html =~ ~s(name="form[_unused_worker_ids]")
    end

    test "the _unused_ marker is absent once an edit form's values are resolved", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "form", "initial_values" => ["1"]})

      html = LiveViewTest.render(session.view)
      refute html =~ ~s(name="form[_unused_worker_ids]")
    end

    test "clearing every chip and submitting sends an explicit empty param, not no param at all", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "form", "initial_values" => ["1"]})

      # "Clear all" empties `@selected` from a previously non-empty
      # selection — distinct from a fresh form that was never touched.
      session.view
      |> LiveViewTest.element("#picker")
      |> LiveViewTest.render_hook("clear", %{})

      html = LiveViewTest.render(session.view)
      assert html =~ ~s(name="form[worker_ids][]" value="")

      session = click_button(session, "Submit")

      assert_has(session, "#submitted", text: ~s("worker_ids" => [""]))
    end
  end

  describe "controlled mode" do
    test "on_select carries the full selection list on every change", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")

      assert_has(session, "#selection", text: ~s(["Casey Cassidy"]))

      session =
        session
        |> type_search("picker-input", "riv")
        |> click_button("Alex Rivers")

      assert_has(session, "#selection", text: ~s(["Casey Cassidy", "Alex Rivers"]))
    end

    test "selecting an option clears the search text so the next pick starts fresh", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")

      assert_has(session, "#picker-input[value='']")
    end
  end

  describe "selected-item rendering (spec 013)" do
    test "a :selected slot renders custom selected items, capped by max_visible with a +N token", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "stack"})

      session =
        session
        |> type_search("picker-input", "cas")
        |> click_button("Casey Cassidy")
        |> type_search("picker-input", "riv")
        |> click_button("Alex Rivers")
        |> type_search("picker-input", "bla")
        |> click_button("Jordan Blake")

      # max_visible=2 → two custom items rendered, the third collapses to "+1".
      assert_has(session, "[data-avatar]", count: 2)
      assert_has(session, "[role='listitem']", count: 2)
      assert_has(session, "[aria-label='1 more selected']", text: "+1")
    end
  end

  describe "result filtering" do
    test "a selected option no longer appears in search results", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = session |> click_button("Casey Cassidy") |> type_search("picker-input", "cas")

      refute_has(session, "[role='option']", text: "Casey Cassidy")
    end

    test "removing a chip makes the option searchable again", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")

      session.view
      |> LiveViewTest.element("button[aria-label='Remove Casey Cassidy']")
      |> LiveViewTest.render_click()

      session = type_search(session, "picker-input", "ca")
      session = type_search(session, "picker-input", "cas")

      assert_has(session, "[role='option']", text: "Casey Cassidy")
    end
  end

  describe "max_selections" do
    test "further selection is prevented and communicated at the cap", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled", "max_selections" => 1})
        |> type_search("picker-input", "cas")

      session = session |> click_button("Casey Cassidy") |> type_search("picker-input", "riv")

      assert_has(session, "li", text: "Maximum of 1 selections reached")
      refute_has(session, "[role='option']", text: "Alex Rivers")
      assert_has(session, "#selection", text: ~s(["Casey Cassidy"]))
    end

    test "removing a chip re-enables selection under the cap", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled", "max_selections" => 1})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")

      session.view
      |> LiveViewTest.element("button[aria-label='Remove Casey Cassidy']")
      |> LiveViewTest.render_click()

      session = type_search(session, "picker-input", "riv")

      assert_has(session, "[role='option']", text: "Alex Rivers")
    end
  end

  describe "chip removal" do
    test "backspace in an empty search input removes the last chip", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = session |> click_button("Casey Cassidy") |> type_search("picker-input", "riv")
      session = click_button(session, "Alex Rivers")

      session.view
      |> LiveViewTest.element("#picker")
      |> LiveViewTest.render_hook("remove_last_chip", %{})

      assert_has(session, "button[aria-label='Remove Casey Cassidy']")
      refute_has(session, "button[aria-label='Remove Alex Rivers']")
      assert_has(session, "#selection", text: ~s(["Casey Cassidy"]))
    end

    test "backspace with no chips selected is a no-op", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "controlled"})

      session.view
      |> LiveViewTest.element("#picker")
      |> LiveViewTest.render_hook("remove_last_chip", %{})

      assert_has(session, "#picker-input")
    end

    test "clear all empties the selection", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = session |> click_button("Casey Cassidy") |> type_search("picker-input", "riv")
      session = session |> click_button("Alex Rivers") |> click_button("Clear all")

      assert_has(session, "#selection", text: "[]")
      refute_has(session, "[role='listitem']")
    end
  end
end
