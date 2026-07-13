defmodule Flicker.SelectFacetsBoundaryTest do
  @moduledoc """
  Regression (Spec 003 v1 scope cut, now lifted): `Flicker.select/1` used to
  strip facet tokens out of the typed text just to shrink the *free-text*
  portion sent to the provider, without ever telling the provider which
  facet filters were active — `Flicker.Providers.AshResource` now composes
  them into its Ash query, but the boundary contract (`Provider.run_search/3`
  is always called with the *full* parsed `%Flicker.Query{}`, `.text` *and*
  `.facets`) has to hold for every provider, Ash-backed or not.

  This exercises that boundary with a hand-built, non-Ash `Flicker.Provider`
  (`Flicker.Providers.Static`'s own moduledoc documents that it ignores
  `.facets` — this spy proves the component still hands them over) so the
  guarantee is visible with no Ash dependency at all.
  """

  use Flicker.Test.ConnCase, async: true

  alias Phoenix.LiveViewTest

  defmodule SpyProvider do
    @moduledoc """
    Records every `%Flicker.Query{}` `search/2` is called with (via an
    `Agent` in `opts[:recorder]`) and echoes `query.facets` back as each
    result's `:sublabel` — lets a test assert on what actually crossed the
    `Flicker.Provider` boundary, not just what's rendered.
    """

    @behaviour Flicker.Provider

    alias Flicker.{Query, Result}

    @impl true
    def search(%Query{} = query, opts) do
      Agent.update(Keyword.fetch!(opts, :recorder), &[query | &1])
      {:ok, [%Result{value: "1", label: "Echo", sublabel: inspect(query.facets)}]}
    end

    @impl true
    def fetch(_values, _opts), do: {:ok, []}
  end

  test "the full parsed Query (text and facets) reaches the provider's search/2" do
    {:ok, recorder} = Agent.start_link(fn -> [] end)

    facets = [%Flicker.Facet{key: :status, type: :enum, values: [:active], value_labels: %{active: "Active"}}]

    session = %{
      "mode" => "controlled",
      "provider" => {SpyProvider, recorder: recorder},
      "facets" => facets
    }

    conn = Plug.Test.init_test_session(build_conn(), session)
    session = visit(conn, "/")

    element = LiveViewTest.element(session.view, "#picker-input")
    LiveViewTest.render_keyup(element, %{"value" => "status:active jo"})
    html = LiveViewTest.render_async(session.view, 2_000)

    assert html =~ "[{:status, :eq, :active}]"

    queries = Agent.get(recorder, & &1)
    assert [%Flicker.Query{text: "jo", facets: [{:status, :eq, :active}]}] = queries
  end
end
