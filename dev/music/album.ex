defmodule Dev.Music.Album do
  @moduledoc """
  A music album belonging to an artist, in the seeded `Dev.Music` demo
  domain (Spec 004's test harness, Spec 005's playground).
  """

  use Ash.Resource,
    domain: Dev.Music,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      public?(true)
      allow_nil?(false)
    end

    attribute :release_date, :date do
      public?(true)
    end

    attribute :track_count, :integer do
      public?(true)
      default(0)
    end
  end

  relationships do
    belongs_to :artist, Dev.Music.Artist do
      public?(true)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:title, :release_date, :track_count, :artist_id])
    end
  end
end
