defmodule Flicker.FacetSuggestTest do
  use ExUnit.Case, async: true

  alias Flicker.{Facet, FacetSuggest, Result}

  doctest Flicker.FacetSuggest

  @status %Facet{
    key: :status,
    label: "Status",
    type: :enum,
    operators: [:eq],
    default_op: :eq,
    values: [:active, :inactive, :on_hiatus],
    value_labels: %{active: "Active", inactive: "Inactive", on_hiatus: "On Hiatus"}
  }

  @worker %Facet{key: :worker, label: "Worker"}

  describe "classify/2" do
    test "delegates to Flicker.CursorContext with the cursor at the end of the text" do
      assert FacetSuggest.classify("stat", [@status]) == {:key, "stat"}
      assert FacetSuggest.classify("status:", [@status]) == {:value, @status, ""}
      assert FacetSuggest.classify("status:acti", [@status]) == {:value, @status, "acti"}
      assert FacetSuggest.classify("bogus:active", [@status]) == :text
    end
  end

  describe "key_suggestions/2" do
    test "'stat' suggests 'status:'" do
      assert [%Result{value: "status:", label: "status:", sublabel: "Status", meta: meta}] =
               FacetSuggest.key_suggestions("stat", [@status, @worker])

      assert meta == %{flicker_facet: true, insert: "status:"}
    end

    test "an empty prefix suggests every facet" do
      assert length(FacetSuggest.key_suggestions("", [@status, @worker])) == 2
    end

    test "a prefix matching no facet key suggests nothing" do
      assert FacetSuggest.key_suggestions("zzz", [@status, @worker]) == []
    end
  end

  describe "enum_value_suggestions/2" do
    test "filters the enum picklist by prefix, matching label or raw value" do
      assert [%Result{label: "On Hiatus", meta: %{insert: "status:on_hiatus "}}] =
               FacetSuggest.enum_value_suggestions(@status, "hiatus")
    end

    test "'act' matches both active and inactive (substring, not prefix-only)" do
      labels = @status |> FacetSuggest.enum_value_suggestions("act") |> Enum.map(& &1.label)
      assert Enum.sort(labels) == ["Active", "Inactive"]
    end

    test "an empty prefix suggests every value" do
      assert length(FacetSuggest.enum_value_suggestions(@status, "")) == 3
    end

    test "returns [] for a non-enum facet" do
      assert FacetSuggest.enum_value_suggestions(@worker, "any") == []
    end
  end

  describe "replace_current_token/2" do
    test "replaces the trailing non-whitespace run" do
      assert FacetSuggest.replace_current_token("status:acti", "status:active ") == "status:active "
      assert FacetSuggest.replace_current_token("foo bar stat", "status:") == "foo bar status:"
      assert FacetSuggest.replace_current_token("", "status:") == "status:"
    end

    test "replaces a whole open-quoted token, not just its trailing word" do
      assert FacetSuggest.replace_current_token(~s(worker:"Casey N), "worker:123 ") == "worker:123 "
    end

    test "replaces a whole closed-quoted token containing whitespace" do
      assert FacetSuggest.replace_current_token(~s(worker:"Casey Nguyen"), "worker:456 ") == "worker:456 "
    end
  end

  describe "resolve_facets/1" do
    test "a hand-built list of Facet structs passes through unchanged" do
      assert FacetSuggest.resolve_facets(%{facets: [@status]}) == [@status]
    end

    test "no resource/source/facets resolves to []" do
      assert FacetSuggest.resolve_facets(%{}) == []
    end

    test "a source module implementing facets/0 is consulted" do
      defmodule FakeProvider do
        @moduledoc false
        @behaviour Flicker.Provider

        @impl true
        def search(_query, _opts), do: {:ok, []}
        @impl true
        def fetch(_values, _opts), do: {:ok, []}
        @impl true
        def facets, do: [%Facet{key: :fake}]
      end

      assert FacetSuggest.resolve_facets(%{source: FakeProvider}) == [%Facet{key: :fake}]
      assert FacetSuggest.resolve_facets(%{source: {FakeProvider, []}}) == [%Facet{key: :fake}]
    end
  end
end
