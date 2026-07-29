defmodule Flicker.Query do
  @moduledoc """
  A search request passed to `c:Flicker.Provider.search/2`, and the result
  of parsing faceted-search input ([Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)).

  ## Fields

    * `:text` — the raw free-text portion, as typed (facet tokens
      stripped out, quotes on whole-token free text unwrapped). Providers
      decide how to match it (the built-in `Flicker.Providers.AshResource`
      runs `ilike`-style matching over its configured search fields); an
      empty string is a valid query (the picker's open-with-no-input
      state — providers typically return a default listing rather than an
      empty result set).
    * `:facets` — active facet filters, as `{key, operator, value}`
      tuples, in the order they appeared in the input. The same key can
      appear more than once (`parse/2` doesn't deduplicate) — repeated
      instances of the same facet are meant to OR together (see
      `to_filter/1`).
    * `:input` — the verbatim string `parse/2` was called with, untouched
      (facet tokens still in place, quoting/casing/whitespace exactly as
      typed). `:text` and `:facets` are *derived* from it and lossy in
      both directions (facet tokens are stripped from `:text`;
      `:facets`' cast values can't reproduce the original literal, e.g.
      `true`/`TRUE`, `7d` vs. its resolved date); `:input` is the one
      field a round-trip (e.g. [Spec 009](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md)
      Level 2's URL-state serialisation) can re-`parse/2` and get back the
      exact same query — the source of truth to persist, never `:text`
      or a reconstruction of `:facets`.
  """

  alias Flicker.Facet

  @typedoc "A parsed facet filter: `{key, operator, cast value}`."
  @type facet_match :: {atom(), Facet.operator(), term()}

  @typedoc "A search request / parsed query."
  @type t :: %__MODULE__{
          text: String.t(),
          facets: [facet_match()],
          input: String.t()
        }

  @enforce_keys [:text]
  defstruct text: nil, facets: [], input: ""

  @operator_symbols [{">=", :gte}, {"<=", :lte}, {"!=", :neq}, {">", :gt}, {"<", :lt}]

  # Key chars allow a trailing `?` (the `active?`-style boolean-attribute
  # naming convention Ash/Elixir use) alongside Unicode letters, digits,
  # and underscore.
  @facet_token ~r/^([\p{L}\p{N}_?]+)(>=|<=|!=|:|>|<)(.*)$/su

  @doc """
  Parses `input` into a `Flicker.Query`, given the facets it should
  recognise.

  This is a pure function: the same `(input, facets)` pair always produces
  the same result, and it never raises — arbitrary typing (unterminated
  quotes, unknown keys, malformed operators, stray backslashes, mid-token
  unicode) always degrades to free text rather than erroring. `facets` is
  a list of `Flicker.Facet.t()`; keys not present in it are never
  recognised as facets.

  ## Grammar

  Input is tokenised on whitespace, except whitespace inside a
  double-quoted span (`worker:"Casey Nguyen"` is one token). Inside quotes,
  `\\"` is a literal quote and `\\\\` is a literal backslash; any other
  backslash is kept as-is. An unterminated quote absorbs the rest of the
  input rather than erroring — the whole thing degrades to free text.

  A token matches the facet grammar when it looks like `key<op>value`,
  where `key` is one or more Unicode letters/digits/underscores (a trailing
  `?`, as in `active?`, is allowed too), `op` is
  one of `:` `>=` `<=` `!=` `>` `<`, and `value` is either a quoted span or
  a run of non-whitespace characters. `key:value` is a match only when:

    * `key` names a facet in `facets`,
    * `op` is `:` (mapped to that facet's `:default_op`) or an operator in
      that facet's `:operators` list,
    * `value` casts cleanly to that facet's `:type` (see `Flicker.Facet`).

  Any failure at any of those steps — unknown key, disallowed operator,
  uncastable value, malformed quoting — degrades the *entire* token to
  free text (appended to `:text` as typed, with a whole-token surrounding
  quote pair stripped and unescaped).

  ## Examples

      iex> facets = [
      ...>   %Flicker.Facet{key: :status, type: :enum, values: [:active, :inactive]},
      ...>   %Flicker.Facet{key: :worker}
      ...> ]
      ...>
      ...> Flicker.Query.parse(~s(status:active worker:"Casey Nguyen" visit notes), facets)
      %Flicker.Query{
        text: "visit notes",
        facets: [{:status, :eq, :active}, {:worker, :eq, "Casey Nguyen"}],
        input: ~s(status:active worker:"Casey Nguyen" visit notes)
      }

      iex> Flicker.Query.parse("unknown:value free text", [])
      %Flicker.Query{text: "unknown:value free text", facets: [], input: "unknown:value free text"}
  """
  @spec parse(String.t(), [Facet.t()]) :: t()
  def parse(input, facets \\ []) when is_binary(input) and is_list(facets) do
    facet_index = Map.new(facets, &{&1.key, &1})

    {reversed_facets, reversed_text} =
      input
      |> tokenize()
      |> Enum.reduce({[], []}, fn token, {facet_acc, text_acc} ->
        case classify(token, facet_index) do
          {:facet, key, op, value} -> {[{key, op, value} | facet_acc], text_acc}
          {:text, text} -> {facet_acc, [text | text_acc]}
        end
      end)

    %__MODULE__{
      text: reversed_text |> Enum.reverse() |> Enum.join(" "),
      facets: Enum.reverse(reversed_facets),
      input: input
    }
  end

  # -- Tokenizer --------------------------------------------------------
  #
  # Splits on ASCII whitespace, except inside a double-quoted span. Quotes
  # are left in place (unescaping happens later, only for tokens that turn
  # out to need it) so the facet grammar below can still see them.

  @spec tokenize(String.t()) :: [String.t()]
  defp tokenize(input), do: input |> do_tokenize([], [], false) |> Enum.reverse()

  defp do_tokenize(<<>>, current, tokens, _in_quotes), do: finish_token(current, tokens)

  defp do_tokenize(<<c::utf8, rest::binary>>, current, tokens, false) when c in [?\s, ?\t, ?\n, ?\r] do
    do_tokenize(rest, [], finish_token(current, tokens), false)
  end

  defp do_tokenize(<<"\\", c::utf8, rest::binary>>, current, tokens, true) do
    do_tokenize(rest, [<<c::utf8>>, "\\" | current], tokens, true)
  end

  defp do_tokenize(<<"\"", rest::binary>>, current, tokens, in_quotes) do
    do_tokenize(rest, ["\"" | current], tokens, not in_quotes)
  end

  defp do_tokenize(<<c::utf8, rest::binary>>, current, tokens, in_quotes) do
    do_tokenize(rest, [<<c::utf8>> | current], tokens, in_quotes)
  end

  defp finish_token([], tokens), do: tokens

  defp finish_token(current, tokens), do: [current |> Enum.reverse() |> IO.iodata_to_binary() | tokens]

  # -- Token classification ----------------------------------------------

  @spec classify(String.t(), %{atom() => Facet.t()}) ::
          {:facet, atom(), Facet.operator(), term()} | {:text, String.t()}
  defp classify(token, facet_index) do
    with [_, key_str, op_str, rest] <- Regex.run(@facet_token, token),
         {:ok, key} <- existing_atom(key_str),
         {:ok, facet} <- Map.fetch(facet_index, key),
         {:ok, op} <- resolve_operator(op_str, facet),
         {:ok, raw_value} <- extract_value(rest),
         {:ok, value} <- cast_value(facet.type, raw_value, facet.values) do
      {:facet, key, op, value}
    else
      _ -> {:text, freetext(token)}
    end
  end

  defp existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  defp resolve_operator(":", facet), do: {:ok, facet.default_op}

  defp resolve_operator(op_str, facet) do
    with {_, op} <- List.keyfind(@operator_symbols, op_str, 0),
         true <- op in facet.operators do
      {:ok, op}
    else
      _ -> :error
    end
  end

  defp extract_value(""), do: :error

  defp extract_value(<<"\"", _::binary>> = rest) do
    case scan_quoted(rest) do
      {:ok, value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  defp extract_value(rest), do: {:ok, rest}

  # A whole token that is itself one balanced quoted span degrades to its
  # unescaped content when it falls through to free text; anything else
  # (unknown key, unterminated quote, ...) is kept verbatim.
  defp freetext(token) do
    case scan_quoted(token) do
      {:ok, value, ""} -> value
      _ -> token
    end
  end

  # Consumes a leading `"..."` span, honouring `\"` and `\\` escapes.
  # Returns the unescaped content and whatever text trails the closing
  # quote — or `:error` if the quote never closes.
  defp scan_quoted(<<"\"", rest::binary>>), do: do_scan_quoted(rest, [])
  defp scan_quoted(_), do: :error

  defp do_scan_quoted(<<>>, _acc), do: :error

  defp do_scan_quoted(<<"\\", c::utf8, rest::binary>>, acc) when c in [?", ?\\] do
    do_scan_quoted(rest, [<<c::utf8>> | acc])
  end

  defp do_scan_quoted(<<"\"", rest::binary>>, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp do_scan_quoted(<<c::utf8, rest::binary>>, acc), do: do_scan_quoted(rest, [<<c::utf8>> | acc])

  # -- Value casting ------------------------------------------------------

  @spec cast_value(Facet.type(), String.t(), [atom()] | nil) :: {:ok, term()} | :error
  defp cast_value(:string, raw, _values), do: {:ok, raw}

  defp cast_value(:integer, raw, _values) do
    case Integer.parse(raw) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  # `Float.parse/1` is not total — it delegates to `:erlang.binary_to_float`,
  # which raises `ArgumentError` when the digits overflow a float. Facet values
  # are arbitrary user input, so an overflowing literal has to degrade to free
  # text like any other uncastable value; without the rescue, typing enough
  # digits into a float facet crashes the host LiveView, contradicting this
  # module's documented "never raises" guarantee.
  defp cast_value(:float, raw, _values) do
    case Float.parse(raw) do
      {float, ""} -> {:ok, float}
      _ -> cast_integer_as_float(raw)
    end
  rescue
    ArgumentError -> :error
  end

  defp cast_integer_as_float(raw) do
    case Integer.parse(raw) do
      {int, ""} -> {:ok, int * 1.0}
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp cast_value(:boolean, raw, _values) do
    case String.downcase(raw) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> :error
    end
  end

  defp cast_value(:date, raw, _values) do
    case Date.from_iso8601(raw) do
      {:ok, date} -> {:ok, date}
      _ -> cast_relative_date(raw)
    end
  end

  defp cast_value(:enum, raw, values) when is_list(values) do
    Enum.find_value(values, :error, fn value -> Atom.to_string(value) == raw and {:ok, value} end)
  end

  defp cast_value(:enum, _raw, _values), do: :error

  # Relative-date grammar (open question in Spec 003): `<n><unit>` where
  # unit is `d` (days), `w` (weeks), `m` (months, approximated as 30 days),
  # or `y` (years, approximated as 365 days) — a fixed set for now.
  defp cast_relative_date(raw) do
    case Regex.run(~r/^(\d+)([dwmy])$/, raw) do
      [_, amount_str, unit] ->
        {:ok, Date.add(Date.utc_today(), -(String.to_integer(amount_str) * days_per_unit(unit)))}

      nil ->
        :error
    end
  end

  defp days_per_unit("d"), do: 1
  defp days_per_unit("w"), do: 7
  defp days_per_unit("m"), do: 30
  defp days_per_unit("y"), do: 365

  if Code.ensure_loaded?(Ash) do
    @doc """
    Builds an Ash `filter_input`-shaped map from `query.facets`: distinct
    facet keys AND together, repeated instances of the same facet key OR
    together. Returns `%{}` (a no-op filter) when there are no facets.

    This only compiles when `ash` is present — the boundary
    [ADR-006](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-006-core-depends-only-on-provider.md)
    draws around Ash-specific capabilities. It shapes plain data (no
    resource, no live query, no `Ash.*` call) for
    `Ash.Query.filter_input/2` to consume — e.g.
    `Ash.Query.filter_input(query, Flicker.Query.to_filter(parsed))`.

    `facets` (a list of `Flicker.Facet.t()`, typically the facet registry
    passed to `parse/2`) resolves each matched key to its
    `Flicker.Facet.target/1` — a relationship path, aggregate, or
    expression-calc name builds a nested filter map instead of a flat
    attribute clause. A key with no matching facet (or the default `[]`)
    falls back to using the key as the attribute name directly.

    ## Examples

        iex> query = %Flicker.Query{text: "", facets: [{:status, :eq, :active}]}
        ...> Flicker.Query.to_filter(query)
        %{"status" => %{"eq" => :active}}

        iex> query = %Flicker.Query{
        ...>   text: "",
        ...>   facets: [{:city, :eq, "Melbourne"}, {:city, :eq, "Sydney"}]
        ...> }
        ...>
        ...> Flicker.Query.to_filter(query)
        %{"or" => [%{"city" => %{"eq" => "Melbourne"}}, %{"city" => %{"eq" => "Sydney"}}]}

        iex> query = %Flicker.Query{text: "", facets: [{:worker, :eq, "id-123"}]}
        ...> facets = [%Flicker.Facet{key: :worker, target: [:worker, :full_name]}]
        ...> Flicker.Query.to_filter(query, facets)
        %{"worker" => %{"full_name" => %{"eq" => "id-123"}}}
    """
    @spec to_filter(t(), [Facet.t()]) :: map()
    def to_filter(%__MODULE__{facets: facets}, facet_defs \\ []) do
      target_index = Map.new(facet_defs, &{&1.key, Facet.target(&1)})

      facets
      |> Enum.group_by(fn {key, _op, _value} -> key end)
      |> Enum.map(fn {key, matches} -> facet_clause(key, matches, target_index) end)
      |> combine_and()
    end

    defp facet_clause(key, [{_key, op, value}], target_index) do
      nested_clause(Map.get(target_index, key, [key]), %{op_string(op) => value})
    end

    defp facet_clause(key, matches, target_index) do
      target = Map.get(target_index, key, [key])

      %{
        "or" =>
          Enum.map(matches, fn {_key, op, value} ->
            nested_clause(target, %{op_string(op) => value})
          end)
      }
    end

    defp nested_clause([last], inner), do: %{to_string(last) => inner}
    defp nested_clause([step | rest], inner), do: %{to_string(step) => nested_clause(rest, inner)}

    defp combine_and([]), do: %{}
    defp combine_and([single]), do: single
    defp combine_and(clauses), do: %{"and" => clauses}

    defp op_string(:eq), do: "eq"
    defp op_string(:neq), do: "not_eq"
    defp op_string(:gt), do: "gt"
    defp op_string(:gte), do: "gte"
    defp op_string(:lt), do: "lt"
    defp op_string(:lte), do: "lte"
    defp op_string(:contains), do: "contains"
  end
end
