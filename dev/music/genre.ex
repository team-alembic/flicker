defmodule Dev.Music.Genre do
  @moduledoc """
  A music genre — the simplest resource in the seeded `Dev.Music` demo
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

    attribute :name, :string do
      public?(true)
      allow_nil?(false)
    end
  end

  relationships do
    has_many(:artists, Dev.Music.Artist)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name])
    end
  end
end
