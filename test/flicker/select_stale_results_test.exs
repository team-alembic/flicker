defmodule Flicker.SelectStaleResultsTest do
  @moduledoc """
  A slower response for an earlier keystroke must never overwrite a newer
  one (Spec 001 acceptance criteria). `Flicker.Components.Select` relies on
  `start_async/3`'s same-name semantics for this: "if there is an in-flight
  task with the same name, the later `start_async` wins and the previous
  task's result is ignored" — this test proves that guarantee holds for a
  provider slow enough to still be running when the next keystroke lands.
  """

  use Flicker.Test.ConnCase, async: true

  alias Phoenix.LiveViewTest

  defmodule SlowThenFastProvider do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(%Flicker.Query{text: "slow"}, _opts) do
      Process.sleep(200)
      {:ok, [%Flicker.Result{value: "1", label: "Stale result for slow"}]}
    end

    def search(%Flicker.Query{text: "fast"}, _opts) do
      {:ok, [%Flicker.Result{value: "2", label: "Fresh result for fast"}]}
    end

    def search(_query, _opts), do: {:ok, []}

    @impl true
    def fetch(_values, _opts), do: {:ok, []}
  end

  test "a slow response for an earlier keystroke never overwrites a newer one" do
    conn = Plug.Test.init_test_session(build_conn(), %{"mode" => "controlled", "provider" => SlowThenFastProvider})
    session = visit(conn, "/")

    element = LiveViewTest.element(session.view, "#picker-input")
    LiveViewTest.render_keyup(element, %{"value" => "slow"})
    LiveViewTest.render_keyup(element, %{"value" => "fast"})

    html = LiveViewTest.render_async(session.view, 2_000)

    assert html =~ "Fresh result for fast"
    refute html =~ "Stale result for slow"
  end

  # The synchronous, non-async facet-suggestion branches of
  # `run_faceted_search/2` must cancel any still-running record-search task
  # from an earlier keystroke — otherwise that task's later completion
  # overwrites the facet suggestions actually on screen.
  test "a synchronous facet-key render is not later overwritten by a slower in-flight record search" do
    facets = [%Flicker.Facet{key: :status}]

    conn =
      Plug.Test.init_test_session(build_conn(), %{
        "mode" => "controlled",
        "provider" => SlowThenFastProvider,
        "facets" => facets
      })

    session = visit(conn, "/")

    element = LiveViewTest.element(session.view, "#picker-input")
    LiveViewTest.render_keyup(element, %{"value" => "slow"})
    LiveViewTest.render_keyup(element, %{"value" => "stat"})

    assert LiveViewTest.render(session.view) =~ "status:"

    html = LiveViewTest.render_async(session.view, 2_000)

    assert html =~ "status:"
    refute html =~ "Stale result for slow"
  end
end
