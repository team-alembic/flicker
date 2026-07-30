defmodule Flicker.TriggerTest do
  @moduledoc """
  `Flicker.Trigger` and the trigger-aware half of `Flicker.CursorContext`
  (Spec 024).

  The load-bearing assertions here are the two the whole feature rests on:

    * a trigger gates **discovery** but not **recognition** — `status:active`
      typed out, pasted, or restored from a URL still classifies as a facet
      value, so sharing a search link keeps working; and
    * a trigger never reaches the grammar — every completion produces canonical
      token text with no trigger grapheme in it, asserted through
      `Flicker.Query.parse/2` rather than by inspecting strings.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Flicker.{CursorContext, Facet, FacetSuggest, Query, Trigger}

  doctest Flicker.Trigger

  @status Facet.new(key: :status, type: :enum, values: [:active, :inactive])
  @tag_facet Facet.new(key: :tag, type: :string)
  @facets [@status, @tag_facet]

  @at %{"@" => :all}

  defp classify(text, trigger, facets \\ @facets) do
    CursorContext.classify(text, String.length(text), facets, trigger)
  end

  describe "parse!/1" do
    test "a bare grapheme means every facet" do
      assert Trigger.parse!("@") == %{"@" => :all}
    end

    test "a map scopes each trigger to its own facets" do
      assert Trigger.parse!(%{"@" => [:worker], "#" => [:tag]}) == %{"@" => [:worker], "#" => [:tag]}
    end

    test "a keyword list works too, since that's what a HEEx map literal often is" do
      assert Trigger.parse!([{"@", [:worker]}]) == %{"@" => [:worker]}
    end

    test "a single atom is wrapped, so scoping to one facet needs no list" do
      assert Trigger.parse!(%{"@" => :worker}) == %{"@" => [:worker]}
    end

    test "nil and an empty config mean no trigger at all" do
      assert Trigger.parse!(nil) == nil
      assert Trigger.parse!(%{}) == nil
      assert Trigger.parse!([]) == nil
    end

    test "the punctuation a host would actually reach for is accepted" do
      for grapheme <- ["@", "#", "/", ":", ">", "!", "~", "$"] do
        assert Trigger.parse!(grapheme) == %{grapheme => :all}
      end
    end

    test "a multi-grapheme trigger is rejected, not truncated" do
      # Silently taking the first character would make `facet_trigger="//"`
      # behave as `/` — a config that reads as working but isn't.
      assert_raise ArgumentError, ~r/single character/, fn -> Trigger.parse!("@@") end
      assert_raise ArgumentError, ~r/single character/, fn -> Trigger.parse!("") end
    end

    test "whitespace is rejected" do
      assert_raise ArgumentError, ~r/whitespace/, fn -> Trigger.parse!(" ") end
    end

    test "a character that can start a facet key is rejected" do
      # `s` would be indistinguishable from the first letter of `status`.
      for grapheme <- ["s", "1", "_", "?", "é"] do
        assert_raise ArgumentError, ~r/starts a facet key/, fn -> Trigger.parse!(grapheme) end
      end
    end

    test "a non-atom facet key is rejected" do
      assert_raise ArgumentError, ~r/facet key atoms/, fn -> Trigger.parse!(%{"@" => ["worker"]}) end
    end

    test "a wholly wrong shape is rejected rather than ignored" do
      assert_raise ArgumentError, ~r/must be a string or a map/, fn -> Trigger.parse!(42) end
    end
  end

  describe "scope/3" do
    test "`:all` is the whole registry" do
      assert Trigger.scope(@at, "@", @facets) == @facets
    end

    test "an explicit list filters it" do
      assert Trigger.scope(%{"@" => [:status]}, "@", @facets) == [@status]
    end

    test "an unconfigured grapheme is nil, distinctly from an empty list" do
      # `nil` means "not facet entry at all"; `[]` means "facet entry whose
      # facets happen to be filtered out". The caller branches on the difference.
      assert Trigger.scope(@at, "#", @facets) == nil
      assert Trigger.scope(%{"@" => [:nonexistent]}, "@", @facets) == []
    end
  end

  describe "graphemes/1" do
    test "sorted, so the hint is stable across renders" do
      assert Trigger.graphemes(%{"@" => :all, "#" => [:tag]}) == ["#", "@"]
    end

    test "nil has none" do
      assert Trigger.graphemes(nil) == []
    end
  end

  describe "classification: the trigger gates discovery" do
    test "a bare word offers no facet keys" do
      assert classify("stat", @at) == :text
      assert classify("status", @at) == :text
    end

    test "a triggered token does, with the trigger dropped from the prefix" do
      assert classify("@stat", @at) == {:key, "stat"}
    end

    test "a bare trigger offers the whole menu" do
      assert classify("@", @at) == {:key, ""}
    end

    test "the same input classifies as a key with no trigger configured" do
      # The regression guard for every existing Spec 003 behaviour.
      assert classify("stat", nil) == {:key, "stat"}
    end

    test "an empty input offers nothing rather than the full key list" do
      assert classify("", @at) == :text
      assert classify("", nil) == {:key, ""}
    end

    test "a trigger mid-token is not a trigger" do
      # `casey@example.com` must stay free text — this is the case that makes an
      # escape syntax unnecessary.
      assert classify("casey@example.com", @at) == :text
    end

    test "a cursor sitting before the trigger hasn't entered facet mode" do
      assert CursorContext.classify("@stat", 0, @facets, @at) == :text
    end

    test "an unconfigured grapheme is just text" do
      assert classify("#stat", @at) == :text
    end

    test "a triggered token in the middle of other text still triggers" do
      assert classify("hello @stat", @at) == {:key, "stat"}
    end
  end

  describe "classification: the trigger does not gate recognition" do
    test "a facet typed out in full still classifies as a value" do
      # The single most important nuance: gating recognition would break every
      # pasted or URL-restored query the moment a host set a trigger.
      assert classify("status:acti", @at) == {:value, @status, "acti"}
    end

    test "including for a facet outside the trigger's scope" do
      trigger = %{"@" => [:tag]}

      assert classify("@stat", trigger) == {:key, "stat"}
      assert Trigger.scope(trigger, "@", @facets) == [@tag_facet]
      # `status` is unreachable via `@`, but still understood when typed.
      assert classify("status:acti", trigger) == {:value, @status, "acti"}
    end

    test "a completed value token still transitions out to text" do
      assert classify("status:active ", @at) == :text
    end
  end

  describe "scoped_facets/4" do
    test "the current trigger's scope drives the suggestion list" do
      trigger = %{"@" => [:status], "#" => [:tag]}

      assert FacetSuggest.scoped_facets("@st", @facets, nil, trigger) == [@status]
      assert FacetSuggest.scoped_facets("#ta", @facets, nil, trigger) == [@tag_facet]
    end

    test "an untriggered token falls back to the whole registry" do
      # The caller is in `{:value, _, _}` or `:text` there, neither of which
      # lists keys — but recognition must see everything.
      assert FacetSuggest.scoped_facets("status:acti", @facets, nil, @at) == @facets
    end

    test "no trigger configured leaves the registry alone" do
      assert FacetSuggest.scoped_facets("stat", @facets, nil, nil) == @facets
    end
  end

  describe "the trigger never reaches the grammar" do
    test "completing a triggered token drops the trigger" do
      assert FacetSuggest.replace_current_token("@stat", "status:") == "status:"
      assert FacetSuggest.replace_current_token("hello @stat", "status:") == "hello status:"
    end

    test "every key suggestion for a triggered prefix parses clean, with no trigger in it" do
      assert [suggestion] = FacetSuggest.key_suggestions("stat", Trigger.scope(@at, "@", @facets))

      insert = suggestion.meta.insert
      refute insert =~ "@"

      completed = FacetSuggest.replace_current_token("@stat", insert <> "active ")
      refute completed =~ "@"

      query = Query.parse(String.trim(completed), @facets)

      assert query.invalid == []
      assert query.facets == [{:status, :eq, :active}]
    end

    test "a literal trigger the user meant as text survives into the query" do
      # `@nope` matches no facet key, so it degrades to free text *including* the
      # trigger — the same way ADR-012 degrades an unknown facet key.
      query = Query.parse("@nope", @facets)

      assert query.text == "@nope"
      assert query.facets == []
      assert query.invalid == []
    end

    test "an email address is free text, not a broken facet" do
      query = Query.parse("casey@example.com", @facets)

      assert query.text == "casey@example.com"
      assert query.facets == []
    end
  end

  property "classification is total for any input, cursor and trigger" do
    check all(
            text <- StreamData.string(:printable, max_length: 40),
            cursor <- StreamData.integer(-5..45),
            trigger <-
              StreamData.member_of([nil, @at, %{"#" => [:tag]}, %{"@" => [:status], "#" => :all}])
          ) do
      assert CursorContext.classify(text, cursor, @facets, trigger) in [:text] or
               match?({:key, _prefix}, CursorContext.classify(text, cursor, @facets, trigger)) or
               match?({:value, _facet, _prefix}, CursorContext.classify(text, cursor, @facets, trigger))
    end
  end

  # `completed == insert` rather than "no grapheme anywhere": `:` is a legal
  # trigger *and* the operator, so `:stat` completing to `status:` legitimately
  # contains one. The invariant is that the completion is exactly the canonical
  # token — nothing prepended, nothing left over.
  property "a key completion is exactly the canonical token, with no trigger prefix" do
    check all(
            prefix <- StreamData.string(:alphanumeric, max_length: 6),
            grapheme <- StreamData.member_of(["@", "#", "/", ":"])
          ) do
      trigger = %{grapheme => :all}
      text = grapheme <> prefix

      case CursorContext.classify(text, String.length(text), @facets, trigger) do
        {:key, key_prefix} ->
          for suggestion <- FacetSuggest.key_suggestions(key_prefix, @facets) do
            completed = FacetSuggest.replace_current_token(text, suggestion.meta.insert)

            assert completed == suggestion.meta.insert
            refute String.starts_with?(completed, grapheme)
          end

        _other ->
          :ok
      end
    end
  end
end
