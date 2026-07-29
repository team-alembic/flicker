defmodule Flicker.FacetValueSourceTest do
  @moduledoc """
  `Flicker.Facet.value_source/1` (Spec 018) — the accessor that makes an enum
  facet and a relationship facet the same thing to an editor, a counter, or a
  suggestion list, differing only in the provider behind them.
  """

  use ExUnit.Case, async: true

  alias Flicker.{Facet, Provider, Query}

  describe ":enum" do
    test "resolves to a Static provider over the closed set" do
      facet = Facet.new(key: :status, type: :enum, values: [:active, :inactive])

      assert {Flicker.Providers.Static, results: results} = Facet.value_source(facet)
      assert Enum.map(results, & &1.value) == [:active, :inactive]
    end

    test "carries display labels, so an editor shows Established not established" do
      facet =
        Facet.new(
          key: :tier,
          type: :enum,
          values: [:established],
          value_labels: %{established: "Established"}
        )

      assert {_module, results: [result]} = Facet.value_source(facet)
      assert result.label == "Established"
    end

    test "falls back to the stringified atom with no labels configured" do
      facet = Facet.new(key: :status, type: :enum, values: [:active])

      assert {_module, results: [result]} = Facet.value_source(facet)
      assert result.label == "active"
    end

    test "the source is actually runnable as a provider" do
      facet =
        Facet.new(key: :tier, type: :enum, values: [:emerging, :established], value_labels: %{emerging: "Emerging"})

      assert {:ok, results} = Provider.run_search(Facet.value_source(facet), %Query{text: "emerg"})
      assert Enum.map(results, & &1.value) == [:emerging]
    end
  end

  describe ":boolean" do
    test "resolves to the fixed true/false pair" do
      assert {Flicker.Providers.Static, results: results} =
               Facet.value_source(Facet.new(key: :verified?, type: :boolean))

      assert Enum.map(results, & &1.value) == [true, false]
      assert Enum.map(results, & &1.label) == ["true", "false"]
    end
  end

  describe "types with no closed set" do
    test "return nil" do
      for type <- [:string, :integer, :float, :date, :datetime, :duration, :date_range, :number_range] do
        assert Facet.value_source(Facet.new(key: :x, type: type)) == nil,
               "#{type} unexpectedly reported a value source"
      end
    end
  end

  describe "value_label/2" do
    test "prefers a configured label" do
      facet = %Facet{key: :status, value_labels: %{active: "Currently active"}}

      assert Facet.value_label(facet, :active) == "Currently active"
    end

    test "falls back to the value as a string" do
      assert Facet.value_label(%Facet{key: :status}, :active) == "active"
      assert Facet.value_label(%Facet{key: :n}, 42) == "42"
    end

    test "falls back for a value absent from the label map" do
      facet = %Facet{key: :status, value_labels: %{active: "Active"}}

      assert Facet.value_label(facet, :archived) == "archived"
    end
  end

  describe "suggestions read their candidates from the same source" do
    test "enum suggestions still match on key or label, not label alone" do
      facet =
        Facet.new(
          key: :tier,
          type: :enum,
          values: [:emerging, :established],
          value_labels: %{emerging: "Up and coming", established: "Established"}
        )

      # `emerg` matches the *key* while the label says "Up and coming" — the
      # generosity that a provider-side label-only match would have lost.
      assert [suggestion] = Flicker.FacetSuggest.enum_value_suggestions(facet, "emerg")
      assert suggestion.label == "Up and coming"

      # ...and the label still matches too.
      assert [_] = Flicker.FacetSuggest.enum_value_suggestions(facet, "coming")
    end

    test "boolean suggestions still filter by prefix" do
      facet = Facet.new(key: :verified?, type: :boolean)

      assert [suggestion] = Flicker.FacetSuggest.enum_value_suggestions(facet, "f")
      assert suggestion.label == "false"
    end
  end
end
