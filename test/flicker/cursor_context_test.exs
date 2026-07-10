defmodule Flicker.CursorContextTest do
  use ExUnit.Case, async: true

  alias Flicker.CursorContext
  alias Flicker.Facet

  doctest Flicker.CursorContext

  @status %Facet{key: :status, type: :enum, values: [:active, :inactive]}
  @worker %Facet{key: :worker}
  @after_facet %Facet{key: :after, type: :date, default_op: :gte, operators: [:gte, :lt]}
  @session_count %Facet{key: :session_count, type: :integer, operators: [:eq, :neq, :gt, :gte, :lt, :lte]}

  @facets [@status, @worker, @after_facet, @session_count]

  describe "classify/3 — key context" do
    test "empty input, cursor at 0" do
      assert CursorContext.classify("", 0, @facets) == {:key, ""}
    end

    test "cursor at the very start of a bare word" do
      assert CursorContext.classify("stat", 0, @facets) == {:key, ""}
    end

    test "cursor at the end of a bare word grows the prefix as it's typed" do
      assert CursorContext.classify("stat", 1, @facets) == {:key, "s"}
      assert CursorContext.classify("stat", 2, @facets) == {:key, "st"}
      assert CursorContext.classify("stat", 3, @facets) == {:key, "sta"}
      assert CursorContext.classify("stat", 4, @facets) == {:key, "stat"}
    end

    test "a fully-typed known key with no operator yet is still key context" do
      assert CursorContext.classify("status", 6, @facets) == {:key, "status"}
    end

    test "a key allowing a trailing `?` (Ash boolean-attribute convention)" do
      active? = %Facet{key: :active?, type: :boolean}
      assert CursorContext.classify("active?", 7, [active?]) == {:key, "active?"}
    end

    test "unknown key with no facets registered at all" do
      assert CursorContext.classify("whatever", 4, []) == {:key, "what"}
    end

    test "a plain multi-word free-text sentence is key context at each word" do
      assert CursorContext.classify("visit notes", 3, @facets) == {:key, "vis"}
      assert CursorContext.classify("visit notes", 9, @facets) == {:key, "not"}
    end
  end

  describe "classify/3 — mid-token edits" do
    test "cursor placed back inside an already-typed key, before the operator" do
      assert CursorContext.classify("status:active", 3, @facets) == {:key, "sta"}
    end

    test "cursor placed back inside an already-typed value" do
      assert CursorContext.classify("status:active", 10, @facets) == {:value, @status, "act"}
    end

    test "cursor right at the key/operator boundary is still key context" do
      assert CursorContext.classify("status:active", 6, @facets) == {:key, "status"}
    end

    test "cursor right after the operator starts an empty value" do
      assert CursorContext.classify("status:active", 7, @facets) == {:value, @status, ""}
    end

    test "cursor mid-way through a multi-character operator freezes the key prefix" do
      # `session_count` is 13 chars; `>=` occupies positions 13 and 14.
      assert CursorContext.classify("session_count>=5", 14, @facets) == {:key, "session_count"}
    end

    test "cursor right after a multi-character operator starts an empty value" do
      assert CursorContext.classify("session_count>=5", 15, @facets) == {:value, @session_count, ""}
    end
  end

  describe "classify/3 — value context, operators" do
    test "the bare `:` form always resolves against a facet's default_op" do
      assert CursorContext.classify("status:", 7, @facets) == {:value, @status, ""}
    end

    test "a legal symbol operator resolves to value context" do
      assert CursorContext.classify("session_count>5", 14, @facets) == {:value, @session_count, ""}
      assert CursorContext.classify("after<2026-01-01", 6, @facets) == {:value, @after_facet, ""}
    end

    test "a symbol operator not in the facet's operators list degrades to text" do
      assert CursorContext.classify("status!=active", 8, @facets) == :text
    end

    test "an operator symbol on a facet whose default `:operators` is just `[:eq]`" do
      assert CursorContext.classify("worker>=x", 8, @facets) == :text
    end
  end

  describe "classify/3 — unknown or illegal facet keys degrade to text" do
    test "unknown key, cursor in the value portion" do
      assert CursorContext.classify("bogus:active", 13, @facets) == :text
    end

    test "unknown key, cursor still inside the key portion stays key context" do
      assert CursorContext.classify("bogus:active", 3, @facets) == {:key, "bog"}
    end

    test "unknown key with no facets registered, cursor in the value portion" do
      assert CursorContext.classify("bogus:active", 13, []) == :text
    end
  end

  describe "classify/3 — cursor inside quoted values" do
    test "cursor right after the opening quote is an empty value prefix" do
      assert CursorContext.classify(~s(worker:"Casey Nguyen"), 8, @facets) == {:value, @worker, ""}
    end

    test "cursor inside the quoted span, including the embedded space" do
      assert CursorContext.classify(~s(worker:"Casey Nguyen"), 13, @facets) == {:value, @worker, "Casey"}
      assert CursorContext.classify(~s(worker:"Casey Nguyen"), 14, @facets) == {:value, @worker, "Casey "}
      assert CursorContext.classify(~s(worker:"Casey Nguyen"), 15, @facets) == {:value, @worker, "Casey N"}
    end

    test "cursor right after the closing quote does not leak the quote character" do
      input = ~s(worker:"Casey Nguyen")
      assert CursorContext.classify(input, String.length(input), @facets) == {:value, @worker, "Casey Nguyen"}
    end

    test "cursor inside an escaped quote sees the unescaped character" do
      input = ~s(worker:"Case\\"y")
      assert CursorContext.classify(input, String.length(input), @facets) == {:value, @worker, ~s(Case"y)}
    end

    test "cursor inside an unterminated quote still classifies as value context" do
      input = ~s(worker:"Casey unterminated)
      assert CursorContext.classify(input, String.length(input), @facets) == {:value, @worker, "Casey unterminated"}
    end
  end

  describe "classify/3 — adjacent tokens" do
    test "cursor right before the separating space belongs to the first token" do
      assert CursorContext.classify("status:active worker:x", 13, @facets) == {:value, @status, "active"}
    end

    test "cursor right after the separating space belongs to the second token" do
      assert CursorContext.classify("status:active worker:x", 14, @facets) == {:key, ""}
    end

    test "cursor in a gap of extra whitespace between tokens is a fresh empty key" do
      input = "status:active   worker:x"
      assert CursorContext.classify(input, 15, @facets) == {:key, ""}
      assert CursorContext.classify(input, 16, @facets) == {:key, ""}
      assert CursorContext.classify(input, 17, @facets) == {:key, "w"}
    end

    test "two facet tokens back to back with a single space never bleed into each other" do
      assert CursorContext.classify("status:active after:7d", 13, @facets) == {:value, @status, "active"}
      assert CursorContext.classify("status:active after:7d", 14, @facets) == {:key, ""}
    end
  end

  describe "classify/3 — after operators" do
    test "cursor immediately after a bare `:` on a known facet" do
      assert CursorContext.classify("status:", 7, @facets) == {:value, @status, ""}
    end

    test "cursor immediately after `>=` on a facet that allows it" do
      assert CursorContext.classify("after>=", 7, @facets) == {:value, @after_facet, ""}
    end

    test "cursor immediately after an operator on an unknown key" do
      assert CursorContext.classify("nope:", 5, @facets) == :text
    end
  end

  describe "classify/3 — every cursor position of a representative input" do
    test "the spec's own worked example, position by position" do
      input = ~s(status:active worker:"Casey Nguyen" after:7d visit notes)

      expected = %{
        0 => {:key, ""},
        6 => {:key, "status"},
        7 => {:value, @status, ""},
        13 => {:value, @status, "active"},
        14 => {:key, ""},
        20 => {:key, "worker"},
        21 => {:value, @worker, ""},
        22 => {:value, @worker, ""},
        23 => {:value, @worker, "C"},
        34 => {:value, @worker, "Casey Nguyen"},
        35 => {:value, @worker, "Casey Nguyen"},
        36 => {:key, ""},
        41 => {:key, "after"},
        42 => {:value, @after_facet, ""},
        44 => {:value, @after_facet, "7d"},
        45 => {:key, ""},
        50 => {:key, "visit"},
        51 => {:key, ""},
        56 => {:key, "notes"}
      }

      for position <- 0..String.length(input) do
        result = CursorContext.classify(input, position, @facets)
        assert match?({:key, _}, result) or match?({:value, %Facet{}, _}, result) or result == :text

        case Map.fetch(expected, position) do
          {:ok, expected_result} -> assert result == expected_result, "position #{position}: #{inspect(result)}"
          :error -> :ok
        end
      end
    end
  end

  describe "classify/3 — cursor clamping" do
    test "a negative cursor clamps to 0" do
      assert CursorContext.classify("status:active", -5, @facets) == {:key, ""}
    end

    test "a cursor past the end of input clamps to the input's length" do
      assert CursorContext.classify("status:active", 999, @facets) == {:value, @status, "active"}
    end
  end
end
