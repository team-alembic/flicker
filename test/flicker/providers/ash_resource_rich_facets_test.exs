if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Providers.AshResourceRichFacetsTest do
    @moduledoc """
    Spec 018's additions to the derivation table: datetime attributes, numeric
    bounds from Ash constraints, and the opt-in overrides for range types and
    multi-value facets.
    """

    use ExUnit.Case, async: true

    alias Flicker.Facet
    alias Flicker.Providers.AshResource
    alias Flicker.Query

    @moduletag :ash

    @resource Flicker.Test.FacetArtist

    defp facet(facets, key) do
      @resource
      |> then(&AshResource.facets(resource: &1, facets: facets))
      |> Enum.find(&(&1.key == key))
    end

    describe "datetime attributes" do
      test "a :utc_datetime attribute derives :datetime, not :date" do
        assert %Facet{type: :datetime} = facet([:signed_at], :signed_at)
      end

      test "the derived datetime facet parses an instant" do
        derived = facet([:signed_at], :signed_at)

        assert %Query{facets: [{:signed_at, :eq, ~U[2026-07-01 09:30:00Z]}]} =
                 Query.parse("signed_at:2026-07-01T09:30:00Z", [derived])
      end

      test "a plain :date attribute still derives :date" do
        assert %Facet{type: :date} = facet([:formed_on], :formed_on)
      end
    end

    describe "numeric bounds from constraints" do
      test "min/max on an integer attribute become :bounds" do
        assert %Facet{type: :integer, bounds: %{min: 0, max: 1_000_000}} = facet([:play_count], :play_count)
      end

      test "min/max on a float attribute become :bounds" do
        derived = facet([:rating], :rating)

        assert derived.type == :float
        assert derived.bounds == %{min: 0.0, max: 5.0}
      end

      test "an unconstrained numeric attribute has no bounds — none are invented" do
        assert %Facet{bounds: nil} = facet([:name], :name)
      end

      test "derived bounds are enforced by the parser" do
        derived = facet([:play_count], :play_count)

        assert %Query{facets: [{:play_count, :eq, 500}]} = Query.parse("play_count:500", [derived])

        assert %Query{facets: [], invalid: [%Query.Invalid{reason: :out_of_bounds, params: params}]} =
                 Query.parse("play_count:2000000", [derived])

        assert params.max == 1_000_000
      end
    end

    describe "range types are opt-in, never derived" do
      test "a date attribute does not become a range on its own" do
        # "created on" and "created between" are different questions, and only
        # the host knows which it wants.
        assert %Facet{type: :date} = facet([:formed_on], :formed_on)
      end

      test "type: :date_range fills in the scalar, operators, and presets" do
        derived = facet([formed_on: [type: :date_range]], :formed_on)

        assert derived.type == :date_range
        assert derived.operators == [:between]
        assert derived.default_op == :between
        assert derived.scalar == :date
        refute Enum.empty?(derived.presets)
      end

      test "the derived range facet parses a range and a preset" do
        derived = facet([formed_on: [type: :date_range]], :formed_on)

        assert %Query{facets: [{:formed_on, :between, range}]} =
                 Query.parse("formed_on:2026-06-01..2026-06-30", [derived])

        assert range.from == ~D[2026-06-01]

        assert %Query{facets: [{:formed_on, :between, %{preset: :last_30_days}}]} =
                 Query.parse("formed_on:last-30-days", [derived])
      end

      test "type: :number_range over a float attribute keeps float endpoints" do
        derived = facet([rating: [type: :number_range]], :rating)

        assert derived.scalar == :float

        assert %Query{facets: [{:rating, :between, %{from: 1.5, to: 4.5}}]} =
                 Query.parse("rating:1.5..4.5", [derived])
      end

      test "type: :number_range over an integer attribute keeps integer endpoints" do
        derived = facet([play_count: [type: :number_range]], :play_count)

        assert derived.scalar == :integer
      end

      test "a range override keeps the bounds already derived from constraints" do
        derived = facet([play_count: [type: :number_range]], :play_count)

        assert derived.bounds == %{min: 0, max: 1_000_000}

        assert %Query{invalid: [%Query.Invalid{reason: :out_of_bounds}]} =
                 Query.parse("play_count:0..2000000", [derived])
      end

      test "type: :datetime_range derives a datetime scalar" do
        derived = facet([signed_at: [type: :datetime_range]], :signed_at)

        assert derived.scalar == :datetime
        assert derived.type == :datetime_range
      end
    end

    describe "multiple? is opt-in" do
      test "an enum facet is single-valued by default" do
        derived = facet([:status], :status)

        refute derived.multiple?
        assert %Query{facets: [{:status, :eq, :active}]} = Query.parse("status:active", [derived])
      end

      test "multiple?: true accepts a comma list as :in" do
        derived = facet([status: [multiple?: true]], :status)

        assert derived.multiple?

        assert %Query{facets: [{:status, :in, [:active, :inactive]}]} =
                 Query.parse("status:active,inactive", [derived])
      end
    end

    describe "other passthrough overrides" do
      test "bounds, editor, validate, suggested and scalar pass straight through" do
        validator = fn _value -> :ok end

        derived =
          facet(
            [
              play_count: [
                bounds: %{min: 1, max: 2, step: 1},
                editor: Flicker.Providers.Static,
                validate: validator,
                suggested: [:today],
                scalar: :float
              ]
            ],
            :play_count
          )

        assert derived.bounds == %{min: 1, max: 2, step: 1}
        assert derived.editor == Flicker.Providers.Static
        assert derived.validate == validator
        assert derived.suggested == [:today]
        assert derived.scalar == :float
      end

      test "an unrecognised override key cannot corrupt the struct" do
        derived = facet([play_count: [not_a_field: :nope]], :play_count)

        assert %Facet{} = derived
        refute Map.has_key?(derived, :not_a_field)
      end
    end
  end
end
