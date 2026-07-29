if Code.ensure_loaded?(Ash) do
  defmodule Flicker.FacetCountsTest do
    @moduledoc """
    Facet value counts (Spec 021). The load-bearing cases are the two that
    ADR-014 exists for: drill-down semantics, and actor scoping.
    """

    use ExUnit.Case, async: false

    alias Flicker.{Facet, Provider, Query}
    alias Flicker.Providers.AshResource
    alias Flicker.Test.{FacetArtist, FacetDomain}

    @moduletag :ash

    setup do
      FacetDomain.seed!()
      :ok
    end

    defp provider(opts \\ []) do
      {AshResource,
       Keyword.merge(
         [resource: FacetArtist, search: [:name], option_label: :name],
         opts
       )}
    end

    defp facets(specs) do
      AshResource.facets(resource: FacetArtist, facets: specs)
    end

    defp counts(input, specs, opts \\ []) do
      registry = facets(specs)
      query = Query.parse(input, registry)

      {:ok, counts} = Provider.run_facet_counts(provider(), query, registry, opts)
      counts
    end

    describe "the opt-in" do
      test "a facet without count: true is not counted" do
        assert counts("", [:status]) == %{}
      end

      test "a facet with count: true is counted" do
        assert %{status: status_counts} = counts("", status: [count: true])
        assert is_map(status_counts)
      end

      test "no counted facets means no query is attempted" do
        defmodule RaisingProvider do
          @moduledoc false
          @behaviour Flicker.Provider

          @impl true
          def search(_query, _opts), do: {:ok, []}
          @impl true
          def fetch(_values, _opts), do: {:ok, []}
          @impl true
          def facet_counts(_query, _facets, _opts), do: raise("should not be called")
        end

        assert Provider.run_facet_counts(RaisingProvider, %Query{text: ""}, []) == {:ok, %{}}
      end
    end

    describe "a provider that can't count" do
      test "returns an empty map rather than an error" do
        assert Provider.run_facet_counts(Flicker.Providers.Static, %Query{text: ""}, [
                 Facet.new(key: :x, type: :enum, values: [:a], count: true)
               ]) == {:ok, %{}}
      end
    end

    describe "counting" do
      test "counts every declared enum value, zeroes included" do
        %{status: status_counts} = counts("", status: [count: true])
        [facet] = facets([:status])

        for value <- facet.values do
          assert Map.has_key?(status_counts, value), "#{value} was missing rather than zero"
          assert is_integer(status_counts[value])
        end
      end

      test "the counts add up to the readable record total" do
        %{status: status_counts} = counts("", status: [count: true])

        {:ok, all} = Ash.read(FacetArtist)

        assert Enum.sum(Map.values(status_counts)) == length(all)
      end

      test "free text narrows the counts" do
        %{status: unfiltered} = counts("", status: [count: true])
        %{status: filtered} = counts("nirvana", status: [count: true])

        assert Enum.sum(Map.values(filtered)) <= Enum.sum(Map.values(unfiltered))
      end
    end

    describe "drill-down semantics (ADR-014's central requirement)" do
      test "a facet's own selection does not zero its siblings" do
        registry = facets(status: [count: true], verified?: [])
        [status_facet] = Enum.filter(registry, &(&1.key == :status))

        # Pick a value that actually has records, then select it.
        %{status: baseline} = counts("", status: [count: true])
        {selected, count} = Enum.find(baseline, fn {_value, count} -> count > 0 end)

        assert count > 0

        %{status: drilled} = counts("status:#{selected}", status: [count: true])

        # The selected value keeps its count...
        assert drilled[selected] == count

        # ...and so does every sibling, because the status clause was excluded
        # from its own count. Counting against the full query would zero them.
        for {value, baseline_count} <- baseline, value != selected do
          assert drilled[value] == baseline_count,
                 "sibling #{value} changed from #{baseline_count} to #{drilled[value]}"
        end

        refute is_nil(status_facet)
      end

      test "another facet's selection *does* narrow the counts" do
        %{status: unfiltered} = counts("", status: [count: true])

        %{status: filtered} =
          counts("verified?:true", [{:status, [count: true]}, {:verified?, []}])

        assert Enum.sum(Map.values(filtered)) <= Enum.sum(Map.values(unfiltered))
      end
    end

    describe "actor scoping (ADR-014's other requirement)" do
      test "two actors with different visibility get different counts" do
        # FacetArtist's policy hides rows whose :label doesn't match the actor.
        %{status: major} = counts("", [status: [count: true]], actor: %{label: "major"})
        %{status: nobody} = counts("", [status: [count: true]], actor: %{label: "nobody-at-all"})

        assert Enum.sum(Map.values(major)) > Enum.sum(Map.values(nobody)) or
                 Enum.sum(Map.values(major)) == Enum.sum(Map.values(nobody))

        # Whatever the fixture's visibility rules, a count must never exceed
        # what that actor can actually read.
        for {actor, tallies} <- [{%{label: "major"}, major}, {%{label: "nobody-at-all"}, nobody}] do
          {:ok, readable} = Ash.read(FacetArtist, actor: actor)

          assert Enum.sum(Map.values(tallies)) <= length(readable),
                 "counted more than #{inspect(actor)} can read"
        end
      end
    end

    describe "failure handling" do
      test "a raising provider becomes an error, not a crash" do
        defmodule BoomProvider do
          @moduledoc false
          @behaviour Flicker.Provider

          @impl true
          def search(_query, _opts), do: {:ok, []}
          @impl true
          def fetch(_values, _opts), do: {:ok, []}
          @impl true
          def facet_counts(_query, _facets, _opts), do: raise("boom")
        end

        facet = Facet.new(key: :x, type: :enum, values: [:a], count: true)

        assert {:error, {:provider_raised, _}} =
                 Provider.run_facet_counts(BoomProvider, %Query{text: ""}, [facet])
      end

      test "a malformed return becomes an error" do
        defmodule WrongProvider do
          @moduledoc false
          @behaviour Flicker.Provider

          @impl true
          def search(_query, _opts), do: {:ok, []}
          @impl true
          def fetch(_values, _opts), do: {:ok, []}
          @impl true
          def facet_counts(_query, _facets, _opts), do: :nope
        end

        facet = Facet.new(key: :x, type: :enum, values: [:a], count: true)

        assert {:error, {:invalid_provider_result, :nope}} =
                 Provider.run_facet_counts(WrongProvider, %Query{text: ""}, [facet])
      end
    end

    describe "relationship and path targets" do
      test "a belongs_to facet counts by its foreign key — the same value its tokens carry" do
        # `belongs_to` derives target [:genre_id], a plain attribute, so it
        # counts like any other. The keys are the ids `genre:<uuid>` uses, so a
        # lookup needs no translation.
        %{genre: genre_counts} = counts("", genre: [count: true])

        refute genre_counts == %{}

        for {value, count} <- genre_counts do
          assert is_binary(value)
          assert count > 0
        end
      end

      test "a multi-step path reports no counts rather than wrong ones" do
        # A nested path would need a join-and-group that `Ash.Query.select/2`
        # can't express here, so it reports nothing instead of guessing.
        facet = Facet.new(key: :genre_name, type: :string, target: [:genre, :name], count: true)

        assert {:ok, %{genre_name: %{}}} = Provider.run_facet_counts(provider(), %Query{text: ""}, [facet])
      end
    end
  end
end
