# The whole module is guarded, not just tagged `:ash` — `@moduletag :ash`
# only skips these tests at *run* time (`mix test --exclude ash`); the
# no-ash CI leg must not even *compile* `use Ash.Resource` (the ad-hoc
# tenant resource below), so the guard has to wrap compilation itself.
if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Providers.AshResourceTest do
    use ExUnit.Case, async: true

    alias Flicker.Provider
    alias Flicker.Providers.AshResource
    alias Flicker.Query

    @moduletag :ash

    setup do
      Dev.Music.seed!()
      :ok
    end

    # `Dev.Music.Artist` is policy-bearing (visibility depends on the actor —
    # see its moduledoc); an actorless read against it is the documented
    # foot-gun ADR-004 calls out, not a case this provider is asked to
    # gracefully degrade. Tests that aren't specifically about actor-scoping
    # pass the anonymous public actor (`label: nil`) so they exercise
    # search/limit/sort/filter behaviour without tripping over that.
    @public_actor %{label: nil}

    defp base_opts(overrides \\ []) do
      Keyword.merge(
        [
          resource: Dev.Music.Artist,
          search: [:name],
          option_label: :name,
          option_sublabel: :label,
          actor: @public_actor
        ],
        overrides
      )
    end

    describe "search/2" do
      test "matches the configured search fields, case-insensitively" do
        assert {:ok, results} = AshResource.search(%Query{text: "casey cassidy"}, base_opts())
        assert [%Flicker.Result{label: "Casey Cassidy"}] = results
      end

      test "blank query returns a default listing" do
        assert {:ok, results} = AshResource.search(%Query{text: ""}, base_opts(limit: 10))
        assert length(results) == 10
      end

      test "respects :limit" do
        assert {:ok, results} = AshResource.search(%Query{text: ""}, base_opts(limit: 3))
        assert length(results) == 3
      end

      test "respects :sort" do
        assert {:ok, results} =
                 AshResource.search(%Query{text: ""}, base_opts(limit: 5, sort: [name: :asc]))

        names = Enum.map(results, & &1.label)
        assert names == Enum.sort(names)
      end

      test "respects a base :filter" do
        assert {:ok, results} =
                 AshResource.search(
                   %Query{text: ""},
                   base_opts(limit: 50, filter: %{"status" => %{"eq" => "active"}})
                 )

        assert results != []

        assert Enum.all?(results, fn %Flicker.Result{value: id} ->
                 Ash.get!(Dev.Music.Artist, id, authorize?: false).status == :active
               end)
      end

      test "an actor sees public artists and artists sharing their label" do
        actor = %{label: "indie"}

        assert {:ok, results} =
                 AshResource.search(%Query{text: ""}, base_opts(limit: 50, actor: actor))

        assert Enum.all?(results, fn %Flicker.Result{value: id} ->
                 artist = Ash.get!(Dev.Music.Artist, id, authorize?: false)
                 is_nil(artist.label) or artist.label == "indie"
               end)

        refute Enum.any?(results, fn %Flicker.Result{value: id} ->
                 Ash.get!(Dev.Music.Artist, id, authorize?: false).label == "major"
               end)
      end

      test "a different actor sees a different slice" do
        indie_actor = %{label: "indie"}
        major_actor = %{label: "major"}

        {:ok, indie_results} =
          AshResource.search(%Query{text: ""}, base_opts(limit: 50, actor: indie_actor))

        {:ok, major_results} =
          AshResource.search(%Query{text: ""}, base_opts(limit: 50, actor: major_actor))

        assert MapSet.new(indie_results, & &1.value) != MapSet.new(major_results, & &1.value)
      end

      test "the public actor (no label) sees only public artists" do
        assert {:ok, results} = AshResource.search(%Query{text: ""}, base_opts(limit: 50))

        assert Enum.all?(results, fn %Flicker.Result{value: id} ->
                 is_nil(Ash.get!(Dev.Music.Artist, id, authorize?: false).label)
               end)
      end
    end

    describe "search/2 with facets" do
      # Regression (Spec 003 v1 scope cut, now lifted): `query.facets` must
      # narrow the candidate set *before* `query.text` runs, not be ignored.
      test "composes query.facets into the Ash query alongside the text match" do
        assert {:ok, results} =
                 AshResource.search(
                   %Query{text: "", facets: [{:status, :eq, :active}]},
                   base_opts(limit: 50, facets: [:status])
                 )

        assert results != []

        assert Enum.all?(results, fn %Flicker.Result{value: id} ->
                 Ash.get!(Dev.Music.Artist, id, authorize?: false).status == :active
               end)
      end

      test "an unmatched facet value narrows results to none, rather than being ignored" do
        assert {:ok, []} =
                 AshResource.search(
                   %Query{text: "", facets: [{:status, :eq, :active}, {:status, :eq, :inactive}]},
                   base_opts(limit: 50, facets: [:status], filter: %{"status" => %{"eq" => "on_hiatus"}})
                 )
      end

      test "distinct facet keys AND, repeated instances of the same key OR" do
        genre = Ash.create!(Dev.Music.Genre, %{name: "Indie Rock"}, authorize?: false)

        Ash.create!(
          Dev.Music.Artist,
          %{name: "Facet Match", status: :active, genre_id: genre.id},
          authorize?: false
        )

        assert {:ok, results} =
                 AshResource.search(
                   %Query{
                     text: "Facet Match",
                     facets: [{:status, :eq, :active}, {:status, :eq, :inactive}]
                   },
                   base_opts(limit: 50, facets: [:status])
                 )

        assert [%Flicker.Result{label: "Facet Match"}] = results
      end
    end

    describe "search/2 with a tenant-scoped resource" do
      defmodule TenantedNote do
        @moduledoc false

        use Ash.Resource,
          domain: Flicker.Providers.AshResourceTest.TenantedDomain,
          data_layer: Ash.DataLayer.Ets

        ets do
          private?(true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        attributes do
          uuid_primary_key(:id)

          attribute :title, :string do
            public?(true)
            allow_nil?(false)
          end

          attribute :org_id, :string do
            public?(true)
            allow_nil?(false)
          end
        end

        actions do
          defaults([:read])

          create :create do
            primary?(true)
            accept([:title, :org_id])
          end
        end
      end

      defmodule TenantedDomain do
        @moduledoc false
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource(TenantedNote)
        end
      end

      test "search only returns rows belonging to the given tenant" do
        Ash.create!(TenantedNote, %{title: "Acme note", org_id: "acme"},
          tenant: "acme",
          authorize?: false
        )

        Ash.create!(TenantedNote, %{title: "Globex note", org_id: "globex"},
          tenant: "globex",
          authorize?: false
        )

        opts = [resource: TenantedNote, search: [:title], option_label: :title, tenant: "acme"]

        assert {:ok, [%Flicker.Result{label: "Acme note"}]} =
                 AshResource.search(%Query{text: ""}, opts)
      end
    end

    describe "fetch/2" do
      test "resolves all N values in a single batch call" do
        {:ok, %{artists: artists}} = {:ok, Dev.Music.seed!()}
        [a, b, c | _] = Enum.filter(artists, &is_nil(&1.label))
        values = Enum.map([a, b, c], & &1.id)

        # `AshResource.fetch/2` builds one `Ash.Query` and issues one
        # `Ash.read/2` for the whole `values` list (ADR-003) — there is no
        # loop over `values` in the implementation to N+1 against.
        assert {:ok, results} = AshResource.fetch(values, base_opts())
        assert MapSet.new(results, & &1.value) == MapSet.new(values)
      end

      test "silently omits values that don't resolve" do
        {:ok, %{artists: [artist | _]}} = {:ok, Dev.Music.seed!()}
        values = [artist.id, Ash.UUID.generate()]

        assert {:ok, results} = AshResource.fetch(values, base_opts())
        assert [%Flicker.Result{value: id}] = results
        assert id == artist.id
      end

      test "an empty list of values resolves to an empty list" do
        assert {:ok, []} = AshResource.fetch([], base_opts())
      end
    end

    describe "Tier-1-style config and a hand-built provider produce identical results" do
      test "same opts through Provider.run_search/3 and direct AshResource.search/2" do
        actor = %{label: "indie"}
        opts = base_opts(limit: 10, sort: [name: :asc], actor: actor)

        assert Provider.run_search({AshResource, opts}, %Query{text: ""}) ==
                 AshResource.search(%Query{text: ""}, opts)
      end
    end
  end
end
