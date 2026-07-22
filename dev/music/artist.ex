defmodule Dev.Music.Artist do
  @moduledoc """
  A music artist — the policy-bearing resource in the seeded `Dev.Music`
  demo domain (Spec 004's test harness, Spec 005's playground).

  Visibility of `:label`-carrying artists depends on the reading actor: an
  artist with `label: nil` is public, one with a label is only visible to
  an actor whose own `:label` matches. Actors are plain maps, e.g.
  `%{label: "indie"}`. This makes actor-scoping assertions first-class
  rather than bolted on (Spec 004's test harness, ADR-004).
  """

  use Ash.Resource,
    domain: Dev.Music,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  # Shared (non-private) table: the select component runs its search in a
  # `start_async` task — a different process from whoever seeded the data
  # — and `Ash.DataLayer.Ets`' `private?: true` tables are `:private`
  # ETS, readable only by their owner process, so a private table seeded in
  # a LiveView's `mount/3` (every playground page) is invisible to that
  # task and every search comes back empty in a real browser (Spec 007's
  # browser suite caught this). Same reasoning as `Flicker.Test.PolicyArtist`;
  # test isolation comes from `Dev.Music.seed!/1`'s deterministic,
  # idempotent data instead of per-process tables.
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
      constraints(one_of: [:active, :inactive, :on_hiatus])
      default(:active)
      allow_nil?(false)
    end

    attribute :formed_on, :date do
      public?(true)
    end

    attribute :monthly_listeners, :integer do
      public?(true)
      default(0)
    end

    # `nil` means public (visible to every actor); otherwise only an actor
    # whose own `:label` matches this value can see the artist.
    attribute :label, :string do
      public?(true)
    end

    attribute :tier, Dev.Music.ArtistTier do
      public?(true)
      default(:emerging)
      allow_nil?(false)
    end
  end

  relationships do
    belongs_to :genre, Dev.Music.Genre do
      public?(true)
      allow_nil?(true)
    end

    has_many(:albums, Dev.Music.Album)
  end

  aggregates do
    count(:albums_count, :albums)
  end

  calculations do
    calculate(:veteran?, :boolean, expr(monthly_listeners > 100_000))
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :status, :formed_on, :monthly_listeners, :label, :tier, :genre_id])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(expr(is_nil(label) or label == ^actor(:label)))
    end
  end
end
