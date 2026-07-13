if Code.ensure_loaded?(Ash) and Code.ensure_loaded?(Cinder) do
  defmodule Flicker.Integrations.CinderTest do
    @moduledoc """
    Unit tests for `Flicker.Integrations.Cinder`
    ([Spec 009](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md)
    Level 2): query composition, URL param round-tripping off the raw
    input string (including quoted values, explicit operators, and
    unicode), and collision-freedom against the params Cinder's own
    `Cinder.UrlSync` manages. The end-to-end URL flow through a live
    view is `Flicker.CinderInteropTest`'s job; this file covers the
    adapter's own contract in isolation.
    """

    use ExUnit.Case, async: true

    alias Dev.Music.Artist
    alias Flicker.Integrations.Cinder, as: FlickerCinder
    alias Flicker.Query

    @moduletag :ash

    describe "query/2" do
      test "a nil filter (search cleared) composes as a no-op filter" do
        assert %Ash.Query{filter: %Ash.Filter{expression: true}} = FlickerCinder.query(Artist, nil)
      end

      test "an empty filter map composes as a no-op filter" do
        assert %Ash.Query{filter: %Ash.Filter{expression: true}} = FlickerCinder.query(Artist, %{})
      end

      test "composes a filter map onto a bare resource" do
        query = FlickerCinder.query(Artist, %{"status" => %{"eq" => :active}})

        assert %Ash.Query{resource: Artist} = query
        assert query.filter != nil
      end

      test "composes onto an already-built query, preserving its sort" do
        base = Ash.Query.sort(Artist, :name)
        query = FlickerCinder.query(base, %{"status" => %{"eq" => :active}})

        assert query.sort == base.sort
        assert query.filter != nil
      end

      test "the composed query filters reads exactly like the Level 1 recipe" do
        Dev.Music.seed!()

        filter =
          "monthly_listeners>=100000"
          |> Query.parse(FlickerCinder.facets(%{resource: Artist, facets: [:monthly_listeners]}))
          |> Query.to_filter()

        names =
          Artist
          |> FlickerCinder.query(filter)
          |> Ash.read!(actor: %{label: nil})
          |> Enum.map(& &1.name)

        assert "Jordan Rivers" in names
        refute "Casey Cassidy" in names
      end
    end

    describe "facets/1" do
      test "resolves Tier 1 resource facets to the same structs Flicker.search/1 uses" do
        facets = FlickerCinder.facets(%{resource: Artist, facets: [:status, :monthly_listeners]})

        assert [%Flicker.Facet{key: :status, type: :enum}, %Flicker.Facet{key: :monthly_listeners, type: :integer}] =
                 facets
      end

      test "passes an already-built facet list through unchanged" do
        facets = [%Flicker.Facet{key: :city}]
        assert FlickerCinder.facets(%{facets: facets}) == facets
      end
    end

    describe "URL round-trip (encode_params/1 -> restore/2)" do
      defp roundtrip(input, facets) do
        params = input |> Query.parse(facets) |> FlickerCinder.encode_params()
        FlickerCinder.restore(params, facets)
      end

      test "a facet query round-trips to an identical parse" do
        facets = FlickerCinder.facets(%{resource: Artist, facets: [:status]})
        {input, query, filter} = roundtrip("status:active free text", facets)

        assert input == "status:active free text"
        assert query == Query.parse("status:active free text", facets)
        assert filter == %{"status" => %{"eq" => :active}}
      end

      test "quoted values round-trip verbatim, not re-quoted or unescaped" do
        facets = [%Flicker.Facet{key: :worker}]
        input = ~s(worker:"Casey \\"The Voice\\" Nguyen" notes)

        {restored, query, _filter} = roundtrip(input, facets)

        assert restored == input
        assert query.facets == [{:worker, :eq, ~s(Casey "The Voice" Nguyen)}]
      end

      test "explicit operators round-trip" do
        facets = FlickerCinder.facets(%{resource: Artist, facets: [:monthly_listeners]})

        {restored, query, _filter} = roundtrip("monthly_listeners>=100000", facets)

        assert restored == "monthly_listeners>=100000"
        assert query.facets == [{:monthly_listeners, :gte, 100_000}]
      end

      test "unicode input round-trips" do
        facets = [%Flicker.Facet{key: :cidade}]

        {restored, query, _filter} = roundtrip(~s(cidade:"São Paulo" émoji 😀), facets)

        assert restored == ~s(cidade:"São Paulo" émoji 😀)
        assert query.facets == [{:cidade, :eq, "São Paulo"}]
        assert query.text == "émoji 😀"
      end

      test "the raw input is the source of truth: a value the struct can't reproduce survives" do
        facets = [%Flicker.Facet{key: :active?, type: :boolean, values: nil}]

        # `TRUE` casts to `true` in the struct — reconstructing the string
        # from `query.facets` would emit `active?:true`, silently rewriting
        # what the user typed. The raw-input round-trip keeps `TRUE`.
        {restored, query, _filter} = roundtrip("active?:TRUE", facets)

        assert restored == "active?:TRUE"
        assert query.facets == [{:active?, :eq, true}]
      end

      test "an empty query encodes to no params at all" do
        assert FlickerCinder.encode_params(Query.parse("", [])) == %{}
      end

      test "restore/2 with no flicker param degrades to the empty query" do
        assert {"", %Query{text: "", facets: []}, %{}} = FlickerCinder.restore(%{"sort" => "-name"}, [])
      end

      test "restore/2 never raises on malformed input" do
        for garbage <- ["\"", "\\", "key:\"unterminated", ":::", String.duplicate("💥", 100)] do
          assert {^garbage, %Query{}, filter} = FlickerCinder.restore(%{"flicker_q" => garbage}, [])
          assert is_map(filter)
        end
      end
    end

    describe "collision-freedom with Cinder's own params" do
      # The exact reserved keys `Cinder.UrlSync.build_url/3` claims for
      # collection state (verified against cinder ~> 0.15) — if a Cinder
      # upgrade ever adds `flicker_q` to this set, this test is the trip
      # wire.
      @cinder_reserved ~w(page sort page_size search after before _filter_fields)

      test "the namespaced param collides with none of Cinder's reserved keys" do
        refute FlickerCinder.url_param() in @cinder_reserved
      end

      test "put_params/2 preserves Cinder's params untouched" do
        cinder_params = %{"page" => "2", "sort" => "-name", "page_size" => "50"}
        query = Query.parse("status:active", [])

        assert FlickerCinder.put_params(cinder_params, query) ==
                 Map.put(cinder_params, "flicker_q", "status:active")
      end

      test "put_params/2 replaces a stale flicker param rather than duplicating it" do
        params = %{"flicker_q" => "old input", "sort" => "-name"}

        assert FlickerCinder.put_params(params, Query.parse("new input", [])) ==
                 %{"flicker_q" => "new input", "sort" => "-name"}
      end

      test "put_params/2 with an empty query removes the flicker param, leaving the rest" do
        params = %{"flicker_q" => "old input", "sort" => "-name"}

        assert FlickerCinder.put_params(params, Query.parse("", [])) == %{"sort" => "-name"}
      end

      test "Cinder's build_url preserves the flicker param as a custom param" do
        # The other direction of the collision guarantee: when Cinder
        # rewrites the URL for its own state change (a sort click), the
        # adapter's param must survive as one of the "custom params"
        # `Cinder.UrlSync.build_url/3` promises to preserve.
        url = Cinder.UrlSync.build_url(%{"sort" => "-name"}, "/artists?flicker_q=status%3Aactive")

        assert %{"flicker_q" => "status:active", "sort" => "-name"} ==
                 url |> URI.parse() |> Map.get(:query) |> URI.decode_query()
      end
    end

    describe "overlapping_fields/2 (the double-filter convention)" do
      test "disjoint fields return an empty list" do
        assert FlickerCinder.overlapping_fields([:status, :tier], [:name, :inserted_at]) == []
      end

      test "a field filtered in both places is reported" do
        assert FlickerCinder.overlapping_fields([:status, :tier], ["status"]) == ["status"]
      end

      test "compares atoms and strings interchangeably" do
        assert FlickerCinder.overlapping_fields(["tier"], [:tier]) == ["tier"]
      end
    end
  end
end
