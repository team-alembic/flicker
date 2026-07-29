# The whole module is guarded, not just tagged `:ash` — see
# `Flicker.Providers.AshResourceTest` for why (the no-ash CI leg must not
# even compile anything that references `Ash.*`).
if Code.ensure_loaded?(Ash) do
  defmodule Flicker.QueryAshFilterTest do
    @moduledoc """
    Verifies `Flicker.Query.to_filter/1`'s output against a real Ash
    resource — not just its shape — by running it through
    `Ash.Query.filter_input/2` and `Ash.read/2` against `Dev.Music.Artist`
    (Spec 003's "verified against generated Ash filters, not just UI
    behaviour" acceptance criterion).
    """
    use ExUnit.Case, async: true

    alias Flicker.Query

    @moduletag :ash

    setup do
      Dev.Music.seed!()
      :ok
    end

    @public_actor %{label: nil}

    defp search(filter) do
      Dev.Music.Artist
      |> Ash.Query.for_read(:read, %{}, actor: @public_actor)
      |> Ash.Query.filter_input(filter)
      |> Ash.read!(actor: @public_actor)
    end

    test "a single eq facet filters to matching records" do
      filter = Query.to_filter(%Query{text: "", facets: [{:status, :eq, :active}]})

      artists = search(filter)
      refute artists == []
      assert Enum.all?(artists, &(&1.status == :active))
    end

    test "distinct facets AND together" do
      filter =
        Query.to_filter(%Query{
          text: "",
          facets: [{:status, :eq, :active}, {:monthly_listeners, :gte, 1}]
        })

      all_active = search(Query.to_filter(%Query{text: "", facets: [{:status, :eq, :active}]}))
      anded = search(filter)

      assert Enum.all?(anded, &(&1.status == :active and &1.monthly_listeners >= 1))
      assert length(anded) <= length(all_active)
    end

    test "repeated same-facet instances OR together" do
      filter =
        Query.to_filter(%Query{
          text: "",
          facets: [{:status, :eq, :active}, {:status, :eq, :on_hiatus}]
        })

      artists = search(filter)
      refute artists == []
      assert Enum.all?(artists, &(&1.status in [:active, :on_hiatus]))
      refute Enum.any?(artists, &(&1.status == :inactive))
    end

    test "a >= comparison excludes records below the threshold" do
      threshold = 100
      filter = Query.to_filter(%Query{text: "", facets: [{:monthly_listeners, :gte, threshold}]})

      artists = search(filter)
      assert Enum.all?(artists, &(&1.monthly_listeners >= threshold))
    end

    test "a != comparison excludes the given value" do
      filter = Query.to_filter(%Query{text: "", facets: [{:status, :neq, :active}]})

      artists = search(filter)
      refute Enum.any?(artists, &(&1.status == :active))
    end

    test "no facets returns the unfiltered actor-scoped read" do
      filter = Query.to_filter(%Query{text: "", facets: []})

      # The filter itself must be a genuine no-op...
      assert filter == %{}

      with_filter = search(filter) |> MapSet.new(& &1.id)

      without_filter =
        Dev.Music.Artist
        |> Ash.Query.for_read(:read, %{}, actor: @public_actor)
        |> Ash.read!(actor: @public_actor)
        |> MapSet.new(& &1.id)

      # ...and constrain nothing. Compared as sets, not counts: this module is
      # `async: true` over a globally-seeded table, so a concurrent seeder can
      # top it up between the two reads. Asserting equal *lengths* made that a
      # latent race; the filtered read can only ever lack records created after
      # it ran, so subset is the assertion that actually holds.
      assert MapSet.subset?(with_filter, without_filter)
      refute Enum.empty?(with_filter)
    end
  end
end
