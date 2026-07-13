defmodule Flicker.CursorContext do
  @moduledoc """
  The cursor-context state machine ([Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)) — a pure function that,
  given typed input, a cursor position, and the active facet registry, says
  what the user is typing *right now*: a facet key, a facet value, or free
  text. The dropdown reads this to pick its result source (key suggestions,
  a facet's value picklist / nested search, or plain free-text handling)
  and its keyboard behaviour, without needing a browser to test any of it.

  This module has no LiveView dependency — `classify/3` is deterministic and
  never raises, so it is exercised directly by unit and property tests
  against arbitrary strings and cursor positions.

  ## Cursor position

  `cursor` is a **codepoint offset** into `input` (`0` is before the first
  character, `String.length(input)` is after the last) — the same unit
  `String.length/1` and `String.slice/3` use. A caller wiring this to a real
  `<input>`'s `selectionStart` (a UTF-16 code-unit offset) converts between
  the two with `from_utf16_offset/2` (and parses the raw event payload with
  `parse_selection_start/1` first — see `Flicker.Components.Search`/
  `Flicker.Components.Select`, or the higher-level `Flicker.FacetSuggest.classify/3`,
  which does both steps for you); out-of-range values (negative, or past the
  end of `input`) are clamped rather than raising.

  ## States

    * `{:key, prefix}` — the cursor sits inside a token before any facet
      operator has been typed (`stat|` inside `stat`, or a plain free-text
      word not yet followed by `:`/`>`/etc.). `prefix` is the token's text
      from its start up to the cursor — filter facet-key suggestions by it.
    * `{:value, facet, prefix}` — the token up to the operator resolves to a
      known facet (`status:` → `%Flicker.Facet{key: :status}`) and the
      operator itself is legal for it (`:` is always legal; a symbol
      operator like `>=` must be in the facet's `:operators`). `prefix` is
      the value text typed so far (quote/escape-unwrapped if the value is
      quoted), truncated at the cursor — filter the facet's picklist /
      nested search by it. The value need not cast cleanly yet — that
      validation belongs to `Flicker.Query.parse/2`, not here, or the state
      would never fire while an enum value is still mid-type.
    * `:text` — the token up to the operator does *not* resolve to a known,
      legal facet (unknown key, or a symbol operator the facet doesn't
      allow) and the cursor sits at or past that operator — this token is
      headed for free text once `Flicker.Query.parse/2` sees it, and there
      is no facet to drive value suggestions from.
  """

  alias Flicker.Facet

  @typedoc "The text of the token from its start up to the cursor."
  @type prefix :: String.t()

  @typedoc "What the cursor is currently positioned to type."
  @type t :: {:key, prefix()} | {:value, Facet.t(), prefix()} | :text

  # Same operator grammar as `Flicker.Query`'s `@facet_token`/`@operator_symbols`
  # — kept in sync by hand since the two modules intentionally don't share
  # code (this one has no need for the parser's tokenizer or value casting).
  # Longest symbols first so `>=` isn't matched as a bare `>`.
  @operators [
    {~c">=", :gte},
    {~c"<=", :lte},
    {~c"!=", :neq},
    {~c":", nil},
    {~c">", :gt},
    {~c"<", :lt}
  ]

  @doc """
  Classifies what `cursor` is positioned to type in `input`, given the
  active `facets`.

  Pure and total: any `input` (empty, malformed, arbitrary Unicode) and any
  `cursor` (including out-of-range integers, which are clamped to
  `0..String.length(input)`) produce one of the three states in `t/0` —
  never an exception.

  ## Examples

      iex> Flicker.CursorContext.classify("stat", 4, [%Flicker.Facet{key: :status}])
      {:key, "stat"}

      iex> Flicker.CursorContext.classify("status:", 7, [%Flicker.Facet{key: :status}])
      {:value, %Flicker.Facet{key: :status}, ""}

      iex> Flicker.CursorContext.classify("status:active", 10, [%Flicker.Facet{key: :status}])
      {:value, %Flicker.Facet{key: :status}, "act"}

      iex> Flicker.CursorContext.classify("bogus:active", 13, [])
      :text

      iex> Flicker.CursorContext.classify("", 0, [])
      {:key, ""}
  """
  @spec classify(String.t(), integer(), [Facet.t()]) :: t()
  def classify(input, cursor, facets) when is_binary(input) and is_integer(cursor) and is_list(facets) do
    codepoints = String.to_charlist(input)
    clamped_cursor = cursor |> max(0) |> min(length(codepoints))
    facet_index = Map.new(facets, &{&1.key, &1})

    {token_chars, token_start} = current_token(codepoints, clamped_cursor)
    classify_token(token_chars, clamped_cursor - token_start, facet_index)
  end

  @doc """
  The start offset (codepoint index) of the token containing `cursor`,
  using the same quote-aware tokenizer `classify/3` does — a double-quoted
  span counts as one token even when it contains whitespace (`worker:"Casey
  N|` is a single token starting at `0`, not split at the space before
  `N`).

  Used by `Flicker.FacetSuggest.replace_current_token/3` to find the
  boundary to splice a chosen suggestion in at, so replacing a token never
  clips mid-quote.

  ## Examples

      iex> Flicker.CursorContext.token_start("foo bar stat", 12)
      8

      iex> Flicker.CursorContext.token_start(~s(worker:"Casey N), 16)
      0
  """
  @spec token_start(String.t(), integer()) :: non_neg_integer()
  def token_start(input, cursor) when is_binary(input) and is_integer(cursor) do
    input |> token_bounds(cursor) |> elem(0)
  end

  @doc """
  The `{start, stop}` codepoint bounds of the token containing `cursor` —
  `token_start/2` is `elem(token_bounds(input, cursor), 0)`. `stop` is that
  same token's end offset (one past its last codepoint), or `start` itself
  when the cursor sits in a whitespace gap between tokens / empty input
  (matching `token_start/2`'s own empty-virtual-token behaviour there).

  Used by `Flicker.FacetSuggest.replace_current_token/3` to know not just
  where a chosen suggestion's replacement text starts, but where the token
  being completed *ends* — so completing a token the cursor has been moved
  back into (mid-token editing, Spec 003's cursor-tracking follow-up, now
  closed) never clobbers whatever free text or other facet tokens follow
  it.

  ## Examples

      iex> Flicker.CursorContext.token_bounds("foo bar stat", 12)
      {8, 12}

      iex> Flicker.CursorContext.token_bounds("status:acti tier:legendary", 10)
      {0, 11}
  """
  @spec token_bounds(String.t(), integer()) :: {non_neg_integer(), non_neg_integer()}
  def token_bounds(input, cursor) when is_binary(input) and is_integer(cursor) do
    codepoints = String.to_charlist(input)
    clamped_cursor = cursor |> max(0) |> min(length(codepoints))
    tokens = tokenize_with_offsets(codepoints)

    case Enum.find(tokens, fn {_chars, start, stop} ->
           start <= clamped_cursor and clamped_cursor <= stop
         end) do
      {_chars, start, stop} -> {start, stop}
      nil -> {clamped_cursor, clamped_cursor}
    end
  end

  @doc """
  Converts `utf16_offset` — a UTF-16 code-unit offset, the unit a real
  `<input>`'s `selectionStart` reports — into the codepoint offset
  `classify/3`/`token_start/2` expect (see the "Cursor position" section
  above). A no-op for the common case: every codepoint Flicker's own
  facet grammar cares about (ASCII, plus the Unicode letters/digits
  `key_char?/1` allows in a key) is exactly one UTF-16 code unit. Only a
  codepoint outside the Basic Multilingual Plane — an emoji typed into a
  free-text facet value, say — is encoded as a two-unit surrogate pair in
  UTF-16 and needs collapsing to the single codepoint it is.

  ## Examples

      iex> Flicker.CursorContext.from_utf16_offset("status:active", 7)
      7

      iex> Flicker.CursorContext.from_utf16_offset("😀status", 3)
      2
  """
  @spec from_utf16_offset(String.t(), non_neg_integer()) :: non_neg_integer()
  def from_utf16_offset(input, utf16_offset) when is_binary(input) and is_integer(utf16_offset) do
    input |> String.to_charlist() |> do_from_utf16_offset(utf16_offset, 0, 0)
  end

  defp do_from_utf16_offset([], _utf16_offset, _consumed, codepoint_index), do: codepoint_index

  defp do_from_utf16_offset(_codepoints, utf16_offset, consumed, codepoint_index) when consumed >= utf16_offset,
    do: codepoint_index

  defp do_from_utf16_offset([codepoint | rest], utf16_offset, consumed, codepoint_index) do
    do_from_utf16_offset(
      rest,
      utf16_offset,
      consumed + utf16_units(codepoint),
      codepoint_index + 1
    )
  end

  defp utf16_units(codepoint) when codepoint > 0xFFFF, do: 2
  defp utf16_units(_codepoint), do: 1

  @doc """
  Parses a `selectionStart` value out of an event payload the colocated
  hook sends (Spec 003's cursor-tracking follow-up, now closed). Every
  value pushed over the LiveView socket arrives as a string (`phx-value-*`
  attributes and pushed event payloads are always strings), so this is
  the one place both `Flicker.Components.Search` and
  `Flicker.Components.Select` parse it back into an integer — or `nil`
  for anything that isn't a clean non-negative integer, which is exactly
  what `Flicker.FacetSuggest.classify/3` treats as "no position reported
  yet" and falls back to the end of the text for (the dead-render / very
  first keystroke case, before the hook's first event has landed).

  ## Examples

      iex> Flicker.CursorContext.parse_selection_start("7")
      7

      iex> Flicker.CursorContext.parse_selection_start(nil)
      nil

      iex> Flicker.CursorContext.parse_selection_start("nope")
      nil
  """
  @spec parse_selection_start(String.t() | integer() | nil) :: non_neg_integer() | nil
  def parse_selection_start(nil), do: nil
  def parse_selection_start(value) when is_integer(value) and value >= 0, do: value
  def parse_selection_start(value) when is_integer(value), do: nil

  def parse_selection_start(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> nil
    end
  end

  def parse_selection_start(_value), do: nil

  # -- Locating the token under the cursor --------------------------------
  #
  # Tokens are whitespace-separated, except whitespace inside a
  # double-quoted span (matching `Flicker.Query`'s tokenizer, so a quoted
  # facet value like `worker:"Casey Nguyen"` is one token even with the
  # cursor resting between "Casey" and "Nguyen"). When the cursor falls in
  # a whitespace gap between tokens (or the input has none at all), it is
  # treated as sitting in an empty virtual token — the start of a fresh one.

  @spec current_token([char()], non_neg_integer()) :: {[char()], non_neg_integer()}
  defp current_token(codepoints, cursor) do
    tokens = tokenize_with_offsets(codepoints)

    case Enum.find(tokens, fn {_chars, start, stop} -> start <= cursor and cursor <= stop end) do
      {chars, start, _stop} -> {chars, start}
      nil -> {[], cursor}
    end
  end

  @spec tokenize_with_offsets([char()]) :: [{[char()], non_neg_integer(), non_neg_integer()}]
  defp tokenize_with_offsets(codepoints), do: do_tokenize(codepoints, 0, nil, [], [], false) |> Enum.reverse()

  defp do_tokenize([], idx, start, current, tokens, _in_quotes), do: finish_token(start, idx, current, tokens)

  defp do_tokenize([c | rest], idx, start, current, tokens, false) when c in [?\s, ?\t, ?\n, ?\r] do
    do_tokenize(rest, idx + 1, nil, [], finish_token(start, idx, current, tokens), false)
  end

  defp do_tokenize([?\\, c | rest], idx, start, current, tokens, true) do
    do_tokenize(rest, idx + 2, start || idx, [c, ?\\ | current], tokens, true)
  end

  defp do_tokenize([?" | rest], idx, start, current, tokens, in_quotes) do
    do_tokenize(rest, idx + 1, start || idx, [?" | current], tokens, not in_quotes)
  end

  defp do_tokenize([c | rest], idx, start, current, tokens, in_quotes) do
    do_tokenize(rest, idx + 1, start || idx, [c | current], tokens, in_quotes)
  end

  defp finish_token(nil, _idx, _current, tokens), do: tokens

  defp finish_token(start, idx, current, tokens), do: [{Enum.reverse(current), start, idx} | tokens]

  # -- Classifying a single token ------------------------------------------

  @spec classify_token([char()], non_neg_integer(), %{atom() => Facet.t()}) :: t()
  defp classify_token(token_chars, rel_cursor, facet_index) do
    key_run = Enum.take_while(token_chars, &key_char?/1)
    key_len = length(key_run)
    after_key = Enum.drop(token_chars, key_len)

    with true <- key_len > 0,
         {op_len, op} <- match_operator(after_key) do
      resolve_within_facet_token(
        token_chars,
        key_run,
        key_len,
        op_len,
        op,
        rel_cursor,
        facet_index
      )
    else
      _ -> {:key, take_prefix(token_chars, rel_cursor)}
    end
  end

  defp resolve_within_facet_token(token_chars, key_run, key_len, op_len, op, rel_cursor, facet_index) do
    cond do
      rel_cursor <= key_len -> {:key, take_prefix(token_chars, rel_cursor)}
      rel_cursor < key_len + op_len -> {:key, List.to_string(key_run)}
      true -> resolve_value(token_chars, key_run, key_len, op_len, op, rel_cursor, facet_index)
    end
  end

  defp resolve_value(token_chars, key_run, key_len, op_len, op, rel_cursor, facet_index) do
    with {:ok, key} <- existing_atom(List.to_string(key_run)),
         {:ok, facet} <- Map.fetch(facet_index, key),
         true <- operator_legal?(op, facet) do
      value_chars =
        token_chars |> Enum.drop(key_len + op_len) |> Enum.take(rel_cursor - key_len - op_len)

      {:value, facet, value_prefix(value_chars)}
    else
      _ -> :text
    end
  end

  defp key_char?(codepoint), do: Regex.match?(~r/^[\p{L}\p{N}_?]$/u, <<codepoint::utf8>>)

  defp match_operator(chars) do
    Enum.find_value(@operators, fn {symbol, op} ->
      if prefix_match?(chars, symbol), do: {length(symbol), op}
    end)
  end

  defp prefix_match?(chars, symbol), do: Enum.take(chars, length(symbol)) == symbol

  defp take_prefix(chars, count), do: chars |> Enum.take(count) |> List.to_string()

  defp existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  defp operator_legal?(nil, _facet), do: true
  defp operator_legal?(op, facet), do: op in facet.operators

  # A leading `"` marks a (possibly still-open) quoted value: the quote
  # itself is dropped and the rest unescaped the same way
  # `Flicker.Query`'s tokenizer does (`\"` and `\\` are escapes, any other
  # backslash is literal) — tolerant of the quote never having been closed
  # yet, since the cursor is mid-type. An unescaped closing quote ends the
  # value there, so a cursor parked just past it doesn't drag the literal
  # quote character into the prefix.
  defp value_prefix([?" | rest]), do: rest |> unescape() |> List.to_string()
  defp value_prefix(chars), do: List.to_string(chars)

  defp unescape([?\\, c | rest]) when c in [?", ?\\], do: [c | unescape(rest)]
  defp unescape([?" | _closed]), do: []
  defp unescape([c | rest]), do: [c | unescape(rest)]
  defp unescape([]), do: []
end
