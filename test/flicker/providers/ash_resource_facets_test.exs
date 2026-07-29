# See `Flicker.Providers.AshResourceTest` for why the whole module — not
# just the tests — is guarded: the no-ash CI leg must not even *compile*
# `Dev.Music.Artist`.
if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Providers.AshResourceFacetsTest do
    use ExUnit.Case, async: true

    alias Flicker.Facet
    alias Flicker.Providers.AshResource
    alias Flicker.Query

    @moduletag :ash

    defp facet(resource, facets, key) do
      resource
      |> then(&AshResource.facets(resource: &1, facets: facets))
      |> Enum.find(&(&1.key == key))
    end

    describe "Ash.Type.Enum attribute -> :enum, the type's own labels" do
      test "derives values and value_labels from the enum type, not a humanised guess" do
        assert %Facet{
                 type: :enum,
                 operators: [:eq],
                 default_op: :eq,
                 values: [:emerging, :established, :legendary],
                 value_labels: %{emerging: "Emerging", established: "Established", legendary: "Legendary"},
                 related: nil
               } = facet(Dev.Music.Artist, [:tier], :tier)
      end

      test "an invalid value is rejected by the parser rather than reaching a filter" do
        [facet] = AshResource.facets(resource: Dev.Music.Artist, facets: [:tier])

        # Reported rather than degraded to free text (ADR-012): the key and
        # operator were both recognised, so the parser can say what was wrong.
        assert %Query{text: "", facets: [], invalid: [%Query.Invalid{reason: :not_in_values}]} =
                 Query.parse("tier:mythical", [facet])

        assert %Query{text: "", facets: [{:tier, :eq, :legendary}]} = Query.parse("tier:legendary", [facet])
      end
    end

    describe "plain atom + one_of constraint -> :enum, humanised labels" do
      test "derives values and a humanised label per value" do
        assert %Facet{
                 type: :enum,
                 operators: [:eq],
                 default_op: :eq,
                 values: [:active, :inactive, :on_hiatus],
                 value_labels: %{active: "Active", inactive: "Inactive", on_hiatus: "On Hiatus"}
               } = facet(Dev.Music.Artist, [:status], :status)
      end
    end

    describe ":boolean attribute -> :boolean" do
      test "derives true/false, eq-only" do
        assert %Facet{type: :boolean, operators: [:eq], default_op: :eq} =
                 facet(Dev.Music.Album, [:explicit?], :explicit?)
      end
    end

    describe "date attribute -> :date, relative values, >= / < ops" do
      test "derives :date with :eq, :gte, :lt operators" do
        assert %Facet{type: :date, operators: [:eq, :gte, :lt], default_op: :eq} =
                 facet(Dev.Music.Artist, [:formed_on], :formed_on)
      end

      test "casts a relative value like 7d through the parser" do
        [facet] = AshResource.facets(resource: Dev.Music.Artist, facets: [after: [attribute: :formed_on, op: :>=]])

        assert %Query{facets: [{:after, :gte, date}]} = Query.parse("after:7d", [facet])
        assert date == Date.add(Date.utc_today(), -7)
      end
    end

    describe "numeric attribute -> numeric type, full comparison operators" do
      test ":integer derives type: :integer" do
        assert %Facet{type: :integer, operators: [:eq, :neq, :gt, :gte, :lt, :lte], default_op: :eq} =
                 facet(Dev.Music.Artist, [:monthly_listeners], :monthly_listeners)
      end

      test "explicit :op overrides the default operator (symbol form, as the spec's registry example writes it)" do
        [facet] =
          AshResource.facets(
            resource: Dev.Music.Artist,
            facets: [after: [attribute: :monthly_listeners, op: :>=]]
          )

        assert facet.default_op == :gte
        assert :gte in facet.operators

        assert %Query{facets: [{:after, :gte, 1000}]} = Query.parse("after>=1000", [facet])
      end
    end

    describe "belongs_to -> string-typed facet + nested-search descriptor" do
      test "derives target from the source attribute and related from the destination resource" do
        assert %Facet{
                 type: :string,
                 operators: [:eq],
                 default_op: :eq,
                 target: [:genre_id],
                 related: %{resource: Dev.Music.Genre}
               } = facet(Dev.Music.Artist, [:genre], :genre)
      end
    end

    describe "has_many -> string-typed facet + nested-search descriptor" do
      test "derives a relationship-path target through the destination's primary key" do
        assert %Facet{
                 type: :string,
                 operators: [:eq],
                 default_op: :eq,
                 target: [:albums, :id],
                 related: %{resource: Dev.Music.Album}
               } = facet(Dev.Music.Artist, [:albums], :albums)
      end
    end

    describe "aggregate -> numeric/boolean per its own resolved type" do
      test "a :count aggregate derives type: :integer" do
        assert %Facet{
                 type: :integer,
                 operators: [:eq, :neq, :gt, :gte, :lt, :lte],
                 default_op: :eq,
                 target: [
                   :albums_count
                 ]
               } = facet(Dev.Music.Artist, [:albums_count], :albums_count)
      end

      test "an explicit :aggregate override redirects which field is introspected" do
        assert %Facet{type: :integer, target: [:albums_count]} =
                 facet(Dev.Music.Artist, [total_albums: [aggregate: :albums_count]], :total_albums)
      end
    end

    describe "calculation -> numeric/boolean per its own resolved type" do
      test "a :boolean calc derives type: :boolean" do
        assert %Facet{type: :boolean, operators: [:eq], default_op: :eq, target: [:veteran?]} =
                 facet(Dev.Music.Artist, [:veteran?], :veteran?)
      end
    end

    describe ":string attribute -> free ilike, no picklist" do
      test "derives type: :string, contains-only, no values" do
        assert %Facet{type: :string, operators: [:contains], default_op: :contains, values: nil} =
                 facet(Dev.Music.Artist, [:name], :name)
      end

      test "matches through the parser as a free contains, not exact eq" do
        [facet] = AshResource.facets(resource: Dev.Music.Artist, facets: [:name])
        assert %Query{facets: [{:name, :contains, "cas"}]} = Query.parse("name:cas", [facet])
      end
    end

    describe "an unknown field name" do
      test "degrades to a plain string facet rather than raising" do
        assert %Facet{type: :string, operators: [:contains], default_op: :contains, target: [:nonexistent]} =
                 facet(Dev.Music.Artist, [:nonexistent], :nonexistent)
      end
    end

    describe "explicit overrides take precedence over derivation" do
      test ":type forces a derivation-independent type, resetting operators/default_op to match" do
        assert %Facet{type: :enum, operators: [:eq], default_op: :eq} =
                 facet(Dev.Music.Artist, [label: [attribute: :label, type: :enum]], :label)
      end

      test ":path walks a relationship to introspect the destination attribute" do
        assert %Facet{type: :string, operators: [:contains], default_op: :contains, target: [:genre, :name]} =
                 facet(Dev.Music.Artist, [genre_name: [path: [:genre, :name]]], :genre_name)
      end

      test ":attribute redirects introspection to a differently-named field, target follows" do
        assert %Facet{type: :integer, target: [:monthly_listeners]} =
                 facet(Dev.Music.Artist, [listeners: [attribute: :monthly_listeners]], :listeners)
      end

      test ":label sets the facet's own display label" do
        assert %Facet{label: "Career tier"} =
                 facet(Dev.Music.Artist, [tier: [label: "Career tier"]], :tier)
      end
    end

    describe "the facet registry composes with Query.parse/2 and Query.to_filter/2 end-to-end" do
      test "a derived relationship facet's target builds a nested Ash filter" do
        genre = Ash.create!(Dev.Music.Genre, %{name: "Rock"}, authorize?: false)

        artist =
          Ash.create!(Dev.Music.Artist, %{name: "Riley Rivers", genre_id: genre.id}, authorize?: false)

        facets = AshResource.facets(resource: Dev.Music.Artist, facets: [:genre])
        query = Query.parse(~s(genre:"#{artist.genre_id}"), facets)

        assert Query.to_filter(query, facets) == %{"genre_id" => %{"eq" => artist.genre_id}}
      end

      test "a derived enum facet round-trips through parse and to_filter" do
        facets = AshResource.facets(resource: Dev.Music.Artist, facets: [:status])
        query = Query.parse("status:active", facets)

        assert Query.to_filter(query, facets) == %{"status" => %{"eq" => :active}}
      end
    end
  end
end
