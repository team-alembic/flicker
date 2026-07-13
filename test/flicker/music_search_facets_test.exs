if Code.ensure_loaded?(Ash) do
  defmodule Flicker.MusicSearchFacetsTest do
    @moduledoc """
    Covers `Dev.Providers.MusicSearch`'s `facets/0`/`query.facets` handling
    directly — the playground's exercise of `facets` inside
    `Flicker.palette/1` end-to-end (Spec 008's now-closed open question).
    `Flicker.PaletteFacetsTest` drives the same behaviour through
    `Flicker.palette/1` itself, against a simpler Tier 1 fixture; this
    module is the one actually wired into the dev playground's `/palette`
    page (`Dev.Live.Palette`), so its own facet logic gets direct coverage
    too.

    Test-support only in spirit (`Dev.Providers.MusicSearch` lives in
    `dev/`, compiled in `:test` for exactly this — see `mix.exs`'s
    `elixirc_paths/1`).
    """

    use ExUnit.Case, async: true

    alias Dev.Providers.MusicSearch
    alias Flicker.Query

    @moduletag :ash

    @actor %{label: nil}

    setup do
      Dev.Music.seed!()
      :ok
    end

    describe "facets/0" do
      test "supports a status facet (Artist's enum) and a type facet (federated group)" do
        keys = MusicSearch.facets() |> Enum.map(& &1.key) |> Enum.sort()
        assert keys == [:status, :type]
      end
    end

    describe "search/2 honouring query.facets" do
      test "no facets returns every group" do
        {:ok, results} = MusicSearch.search(%Query{text: ""}, actor: @actor, limit: 200)
        groups = results |> Enum.map(& &1.group) |> Enum.uniq() |> Enum.sort()

        assert groups == ["Albums", "Artists", "Genres"]
      end

      test "a type: facet narrows to just that resource group" do
        query = Query.parse("type:album", MusicSearch.facets())
        {:ok, results} = MusicSearch.search(query, actor: @actor, limit: 200)

        assert results != []
        assert Enum.all?(results, &(&1.group == "Albums"))
      end

      test "a status: facet narrows Artist results, leaving Albums/Genres untouched" do
        query = Query.parse("status:active", MusicSearch.facets())
        {:ok, results} = MusicSearch.search(query, actor: @actor, limit: 200)

        groups = results |> Enum.map(& &1.group) |> Enum.uniq() |> Enum.sort()
        assert groups == ["Albums", "Artists", "Genres"]

        artist_names = results |> Enum.filter(&(&1.group == "Artists")) |> Enum.map(& &1.label)
        assert "Casey Cassidy" in artist_names
      end

      test "status: and type: compose (AND) to just active artists" do
        query = Query.parse("status:active type:artist", MusicSearch.facets())
        {:ok, results} = MusicSearch.search(query, actor: @actor, limit: 200)

        assert results != []
        assert Enum.all?(results, &(&1.group == "Artists"))
      end
    end
  end
end
