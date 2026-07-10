if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Test.PolicyArtist do
    @moduledoc """
    A tiny policy-bearing Ash resource for exercising actor scoping through
    the *full* `Flicker.select/1` component (not just the provider —
    `Flicker.Providers.AshResourceTest` already covers that).

    Deliberately **not** `private?: true` ETS, unlike `Dev.Music.Artist`:
    the select component's search runs in a `start_async` task — a
    different process from the one that seeds this resource — and
    `Ash.DataLayer.Ets`'s private tables are scoped by the calling
    process's `Process` dictionary, so a private table seeded in the test
    process would be invisible to that task. A shared table sidesteps it;
    test isolation instead comes from each row's fixed, distinct `:label`.
    """

    use Ash.Resource,
      domain: Flicker.Test.PolicyDomain,
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
      # can read the row (mirrors `Dev.Music.Artist`).
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

  defmodule Flicker.Test.PolicyDomain do
    @moduledoc "The domain for `Flicker.Test.PolicyArtist` (test-support only)."

    use Ash.Domain

    resources do
      resource(Flicker.Test.PolicyArtist)
    end

    @fixture_rows [
      %{name: "Alex Cassidy", label: "indie"},
      %{name: "Jordan Blake", label: "major"},
      %{name: "Casey Public", label: nil}
    ]

    @doc """
    Seeds the fixed fixture rows, once — checks for existing data first so
    it's safe to call from every test that needs it (the shared, non-private
    ETS table persists across the whole test run, not per-test).
    """
    @spec seed!() :: :ok
    def seed! do
      if Ash.count!(Flicker.Test.PolicyArtist, authorize?: false) == 0 do
        Enum.each(@fixture_rows, &Ash.create!(Flicker.Test.PolicyArtist, &1, authorize?: false))
      end

      :ok
    end
  end
end
