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

  @active? %Facet{key: :active?, label: "Active?", type: :boolean, operators: [:eq], default_op: :eq}

  describe "classify/2" do
    test "delegates to Flicker.CursorContext with the cursor at the end of the text" do
      assert FacetSuggest.classify("stat", [@status]) == {:key, "stat"}
      assert FacetSuggest.classify("status:", [@status]) == {:value, @status, ""}
      assert FacetSuggest.classify("status:acti", [@status]) == {:value, @status, "acti"}
      assert FacetSuggest.classify("bogus:active", [@status]) == :text
    end
  end

  describe "classify/3" do
    test "an explicit nil cursor falls back to the end of the text, same as classify/2" do
      assert FacetSuggest.classify("status:acti", [@status], nil) == FacetSuggest.classify("status:acti", [@status])
    end

    # Regression: a mid-token cursor must classify at the real position,
    # not "at the end" — the v1 scope cut this closes (spec-003's
    # implementation notes).
    test "a real, mid-token cursor classifies there instead of at the end" do
      # Cursor 3 sits inside "stat" of "status:active" — still key context,
      # even though the text is a fully-formed, known facet token.
      assert FacetSuggest.classify("status:active", [@status], 3) == {:key, "sta"}
    end

    test "cursor is a UTF-16 offset, converted before classifying (an explicit cursor at the true end still matches the nil fallback)" do
      text = "status:acti"
      assert FacetSuggest.classify(text, [@status], String.length(text)) == FacetSuggest.classify(text, [@status])
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

    test "returns [] for a non-enum, non-boolean facet" do
      assert FacetSuggest.enum_value_suggestions(@worker, "any") == []
    end
  end

  # Regression: spec-003's type table promises `:boolean` facets suggest
  # `true`/`false`, but only `:enum` had value suggestions wired up.
  describe "enum_value_suggestions/2 with a :boolean facet" do
    test "an empty prefix suggests both true and false" do
      assert [%Result{label: "true", meta: %{insert: "active?:true "}}, %Result{label: "false"}] =
               FacetSuggest.enum_value_suggestions(@active?, "")
    end

    test "prefix 'f' suggests only false" do
      assert [%Result{label: "false", meta: %{insert: "active?:false "}}] =
               FacetSuggest.enum_value_suggestions(@active?, "f")
    end

    test "prefix 't' suggests only true" do
      assert [%Result{label: "true"}] = FacetSuggest.enum_value_suggestions(@active?, "t")
    end

    test "a prefix matching neither suggests nothing" do
      assert FacetSuggest.enum_value_suggestions(@active?, "zzz") == []
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

  describe "replace_current_token/3" do
    test "an explicit nil cursor is byte-identical to replace_current_token/2" do
      assert FacetSuggest.replace_current_token("status:acti", "status:active ", nil) ==
               FacetSuggest.replace_current_token("status:acti", "status:active ")
    end

    # Regression: completing a token the cursor was moved back into must
    # not clobber whatever follows it — the naive "always slice to the end
    # of the text" approach `replace_current_token/2` alone would take
    # (mirroring the v1 assumption that the cursor is always at the end).
    test "a mid-token cursor completes that token and preserves what follows it" do
      assert FacetSuggest.replace_current_token("status:acti tier:legendary", "status:active ", 10) ==
               "status:active tier:legendary"
    end

    test "the trailing space `replacement` carries doesn't double up with the separator that followed the old token" do
      assert FacetSuggest.replace_current_token("status:acti free text", "status:active ", 10) ==
               "status:active free text"
    end

    test "a mid-token cursor takes a UTF-16 offset, converted before the token boundary is found" do
      # An astral codepoint ahead of the cursor shifts a naive same-offset
      # read one codepoint short — this still completes "stat" whole.
      # "😀 stat" is 6 codepoints but 7 UTF-16 units (the emoji is a
      # surrogate pair); 7 is the true end of the string.
      assert FacetSuggest.replace_current_token("😀 stat", "status:", 7) == "😀 status:"
    end
  end

  describe "resolve_facets/1" do
    test "a hand-built list of Facet structs passes through unchanged" do
      assert FacetSuggest.resolve_facets(%{facets: [@status]}) == [@status]
    end

    # Regression: the Ash-guarded `resource:` clause used to be checked
    # before the explicit-`%Facet{}` passthrough, so `%{resource: ...,
    # facets: [%Facet{} | _]}` was sent into `AshResource.facets/1` (which
    # expects atom specs / `{key, overrides}` pairs, not already-built
    # structs) and crashed. Explicit structs must win regardless of
    # `resource:`.
    if Code.ensure_loaded?(Ash) do
      @tag :ash
      test "explicit Facet structs win even when resource: is also set" do
        assert FacetSuggest.resolve_facets(%{resource: Dev.Music.Artist, facets: [@status, @worker]}) ==
                 [@status, @worker]
      end
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
