if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Test.FacetGenre do
    @moduledoc """
    A tiny policy-bearing related resource for exercising `Flicker.search/1`'s
    nested, actor-scoped relationship-facet search (Spec 003) through the
    *full* component — not just `Flicker.FacetSuggest.related_search/3`.

    Deliberately **not** `private?: true` ETS (mirrors
    `Flicker.Test.PolicyArtist`): the nested search runs in a `start_async`
    task, a different process from the one seeding this resource, and
    `Ash.DataLayer.Ets`'s private tables are scoped by the calling process.
    """

    use Ash.Resource,
      domain: Flicker.Test.FacetDomain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    attributes do
      uuid_primary_key(:id)

      attribute :name, :string do
        public?(true)
        allow_nil?(false)
      end

      # `nil` is public; otherwise only an actor whose own `:label` matches
      # can read the row.
      attribute :label, :string do
        public?(true)
      end
    end

    actions do
      defaults([:read])

      create :create do
        primary?(true)
        accept([:name, :label])
      end
    end

    policies do
      policy action_type(:read) do
        authorize_if(expr(is_nil(label) or label == ^actor(:label)))
      end
    end
  end

  defmodule Flicker.Test.FacetArtist do
    @moduledoc """
    A tiny resource carrying an enum facet and a `belongs_to` relationship
    facet, for exercising `Flicker.search/1` and `facets` on `Flicker.select/1`
    end-to-end (Spec 003) — one row per `docs/specs/spec-003-faceted-search.md`
    type-table entry this fixture is meant to cover (`:enum`, relationship).
    """

    use Ash.Resource,
      domain: Flicker.Test.FacetDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    attributes do
      uuid_primary_key(:id)

      attribute :name, :string do
        public?(true)
        allow_nil?(false)
      end

      attribute :status, :atom do
        public?(true)
        constraints(one_of: [:active, :inactive])
        default(:active)
        allow_nil?(false)
      end

      # A `:boolean`-typed facet (Spec 003's type table) — carries a
      # trailing `?`, the Ash/Elixir boolean-attribute naming convention
      # `Flicker.Query`'s facet-token grammar explicitly allows in a key.
      attribute :verified?, :boolean do
        public?(true)
        default(false)
        allow_nil?(false)
      end

      # Spec 018: `min`/`max` constraints are what `:bounds` derives from, and
      # a datetime attribute is what derives `:datetime` rather than `:date`.
      attribute :play_count, :integer do
        public?(true)
        constraints(min: 0, max: 1_000_000)
        default(0)
      end

      attribute :rating, :float do
        public?(true)
        constraints(min: 0.0, max: 5.0)
      end

      attribute :signed_at, :utc_datetime do
        public?(true)
      end

      attribute :formed_on, :date do
        public?(true)
      end
    end

    relationships do
      belongs_to :genre, Flicker.Test.FacetGenre do
        public?(true)
        allow_nil?(true)
      end
    end

    actions do
      defaults([:read])

      create :create do
        primary?(true)

        accept([
          :name,
          :status,
          :genre_id,
          :verified?,
          :play_count,
          :rating,
          :signed_at,
          :formed_on
        ])
      end
    end
  end

  defmodule Flicker.Test.FacetDomain do
    @moduledoc "The domain for `Flicker.Test.FacetArtist`/`Flicker.Test.FacetGenre` (test-support only)."

    use Ash.Domain

    resources do
      resource(Flicker.Test.FacetArtist)
      resource(Flicker.Test.FacetGenre)
    end

    @doc """
    Seeds a fixed fixture — once — so it's safe to call from every test that
    needs it (the shared, non-private ETS tables persist across the whole
    test run). Returns the seeded genres/artists by name for assertions.
    """
    @spec seed!() :: %{genres: %{String.t() => struct()}, artists: [struct()]}
    def seed! do
      # `:global.trans/2` serialises concurrent seeders (several `LiveView`
      # mounts race to seed under `async: true`) so the `if count == 0`
      # check-then-create below can't double-seed — two racing readers both
      # seeing `0` and both creating "Indie Rock" twice, which would break
      # any assertion counting on exactly one match.
      :global.trans({__MODULE__, self()}, fn ->
        if count_genres!() == 0 do
          indie = Ash.create!(Flicker.Test.FacetGenre, %{name: "Indie Rock"}, authorize?: false)

          major =
            Ash.create!(Flicker.Test.FacetGenre, %{name: "Major Pop", label: "major"}, authorize?: false)

          Ash.create!(
            Flicker.Test.FacetArtist,
            %{name: "Riley Rivers", status: :active, genre_id: indie.id},
            authorize?: false
          )

          Ash.create!(
            Flicker.Test.FacetArtist,
            %{name: "Jordan Blake", status: :inactive, genre_id: major.id},
            authorize?: false
          )

          # Shares the "Jo" free-text prefix with "Jordan Blake" but a
          # different `:status` — lets a test prove a facet filter actually
          # narrows *which records* the free-text match considers, not just
          # which text it runs against (`status:active jo` should return
          # this artist alone).
          Ash.create!(
            Flicker.Test.FacetArtist,
            %{name: "Joey Turner", status: :active, genre_id: indie.id},
            authorize?: false
          )
        end
      end)

      genres = Map.new(Ash.read!(Flicker.Test.FacetGenre, authorize?: false), &{&1.name, &1})
      artists = Ash.read!(Flicker.Test.FacetArtist, authorize?: false)
      %{genres: genres, artists: artists}
    end

    # The shared (non-private) ETS table's owner process starts lazily on
    # first access — under `async: true`, several `LiveView` mounts can race
    # to seed at once, and the very first read can hit the owner process
    # before it's finished starting (`:table_not_found`). A handful of
    # short retries rides out that startup window without weakening the
    # "seed once" idempotency (`seed!/0`'s own `if count == 0` still guards
    # against double-seeding once the table exists).
    defp count_genres!(attempts \\ 20) do
      Ash.count!(Flicker.Test.FacetGenre, authorize?: false)
    rescue
      error ->
        if attempts > 0 do
          Process.sleep(5)
          count_genres!(attempts - 1)
        else
          reraise error, __STACKTRACE__
        end
    end
  end
end
