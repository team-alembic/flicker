defmodule Flicker.Facet.Cast do
  @moduledoc """
  Value casting and validation for facets ([Spec 018](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-018-rich-facet-types.md)).

  One implementation, two entry points:

    * `cast/4` — the successful path, returning `{:ok, operator, value}`. The
      operator comes back because casting can *refine* it: `:` on a range
      facet resolves to `:between`, and on a `multiple?: true` facet resolves
      to `:in` or stays `:eq` depending on whether the literal has commas.
    * `validate/4` — the same work, discarding the value and returning
      `:ok | {:error, {reason, params}}`.

  Because they share an implementation, a validation reason can never exist
  without the cast having rejected the value that produced it, and vice
  versa — which is what
  [ADR-012](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-012-parse-reports-invalid-facet-tokens.md)
  needs to report a known facet's bad value instead of silently degrading it.

  ## The grammar this casts

  Locale-invariant throughout, per
  [ADR-013](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-013-canonical-tokens-localised-display.md):
  ISO 8601 dates, `.` as the decimal separator, `..` for ranges, `,` for
  lists, canonical preset and enum ids. No locale reaches this module.

    * **Scalars** — `42`, `1.5`, `true`, `2026-07-01`, `2026-07-01T09:30:00Z`,
      plus relative dates (`7d`, `2w`, `1m`, `1y`) and named dates (`today`,
      `yesterday`).
    * **Durations** — `90s`, `15m`, `2h30m`, `1d`, cast to integer seconds.
    * **Ranges** — `from..to`, `..to`, `from..`, or a bare scalar (a
      single-day range for `:date_range`; the whole UTC day for
      `:datetime_range`), or a preset token.
    * **Lists** — `a,b,c`, only on a `multiple?: true` facet.

  ## Reference date and week start

  `cast/4` and `validate/4` take `:today` and `:first_day_of_week` opts
  rather than reading the clock or a locale, so relative dates and
  week-sensitive presets are testable at a fixed point. They default to
  `Date.utc_today/0` and `1` (Monday, the ISO 8601 default) — which is what
  `Flicker.Query.parse/2` passes when a caller says nothing.
  """

  alias Flicker.Facet
  alias Flicker.Facet.{Preset, Range}

  @typedoc "Why a value was rejected, and the details a message needs."
  @type reason :: {atom(), map()}

  @range_types [:date_range, :datetime_range, :number_range]

  @duration_units %{"s" => 1, "m" => 60, "h" => 3_600, "d" => 86_400}
  @relative_date_units %{"d" => 1, "w" => 7}

  @doc """
  The range-typed facet types — the ones whose cast value is a
  `Flicker.Facet.Range`.

  ## Examples

      iex> Flicker.Facet.Cast.range_types()
      [:date_range, :datetime_range, :number_range]
  """
  @spec range_types() :: [Facet.type()]
  def range_types, do: @range_types

  @doc """
  Casts `raw` for `facet` under the requested `operator`.

  Returns `{:ok, resolved_operator, value}`, or `{:error, {reason, params}}`
  — never raises, for any input.

  ## Examples

      iex> facet = %Flicker.Facet{key: :price, type: :integer}
      ...> Flicker.Facet.Cast.cast(facet, "42", :eq)
      {:ok, :eq, 42}

      iex> facet = %Flicker.Facet{key: :price, type: :number_range}
      ...> Flicker.Facet.Cast.cast(facet, "10..50", :between)
      {:ok, :between, %Flicker.Facet.Range{from: 10, to: 50}}

      iex> facet = %Flicker.Facet{key: :price, type: :integer}
      ...> Flicker.Facet.Cast.cast(facet, "abc", :eq)
      {:error, {:bad_integer, %{value: "abc"}}}
  """
  @spec cast(Facet.t(), String.t(), Facet.operator(), keyword()) ::
          {:ok, Facet.operator(), term()} | {:error, reason()}
  def cast(facet, raw, operator, opts \\ []) do
    with {:ok, resolved_op, value} <- do_cast(facet, raw, operator, opts),
         :ok <- check_bounds(facet, value),
         :ok <- run_custom_validator(facet, value) do
      {:ok, resolved_op, value}
    end
  end

  @doc """
  `cast/4` with the value discarded — `:ok`, or the reason it failed.

  ## Examples

      iex> facet = %Flicker.Facet{key: :price, type: :integer}
      ...> Flicker.Facet.Cast.validate(facet, "42", :eq)
      :ok

      iex> facet = %Flicker.Facet{key: :price, type: :integer, bounds: %{min: 0, max: 100}}
      ...> Flicker.Facet.Cast.validate(facet, "900", :eq)
      {:error, {:out_of_bounds, %{min: 0, max: 100, value: 900}}}
  """
  @spec validate(Facet.t(), String.t(), Facet.operator(), keyword()) :: :ok | {:error, reason()}
  def validate(facet, raw, operator, opts \\ []) do
    case cast(facet, raw, operator, opts) do
      {:ok, _op, _value} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # -- Dispatch by facet type -------------------------------------------

  defp do_cast(%Facet{type: type} = facet, raw, operator, opts) when type in @range_types do
    cast_range(facet, raw, operator, opts)
  end

  defp do_cast(%Facet{multiple?: true} = facet, raw, operator, opts) do
    cast_list(facet, raw, operator, opts)
  end

  defp do_cast(facet, raw, operator, opts) do
    with {:ok, value} <- cast_scalar(facet, facet.type, raw, opts) do
      {:ok, operator, value}
    end
  end

  # -- Ranges ------------------------------------------------------------

  # A preset token wins over the range literal: `last-30-days` contains no
  # `..` and would otherwise fall through to a bare-scalar cast and fail.
  defp cast_range(facet, raw, operator, opts) do
    cond do
      preset = matching_preset(facet, raw) ->
        {:ok, :between, Preset.resolve(preset, reference_date(opts), first_day_of_week(opts))}

      String.contains?(raw, "..") ->
        cast_range_literal(facet, raw, opts)

      true ->
        cast_bare_scalar_range(facet, raw, operator, opts)
    end
  end

  defp matching_preset(%Facet{type: :number_range}, _raw), do: nil

  defp matching_preset(facet, raw) do
    Preset.find_by_token(raw, facet.presets || Preset.builtin())
  end

  defp cast_range_literal(facet, raw, opts) do
    [from_raw, to_raw] = split_range(raw)

    with {:ok, from} <- cast_endpoint(facet, from_raw, opts),
         {:ok, to} <- cast_endpoint(facet, to_raw, opts),
         :ok <- reject_fully_open(from, to, raw),
         :ok <- check_order(from, to) do
      {:ok, :between, %Range{from: from, to: expand_upper(facet, to, to_raw)}}
    end
  end

  # Only the *first* `..` splits, so a malformed `1..2..3` fails on the
  # endpoint cast rather than silently dropping a component.
  defp split_range(raw) do
    case String.split(raw, "..", parts: 2) do
      [from, to] -> [from, to]
    end
  end

  defp cast_endpoint(_facet, "", _opts), do: {:ok, nil}

  defp cast_endpoint(facet, raw, opts) do
    cast_scalar(facet, Facet.scalar(facet), raw, opts)
  end

  defp reject_fully_open(nil, nil, raw), do: {:error, {:incomplete_range, %{value: raw}}}
  defp reject_fully_open(_from, _to, _raw), do: :ok

  defp check_order(nil, _to), do: :ok
  defp check_order(_from, nil), do: :ok

  defp check_order(from, to) do
    if compare(from, to) == :gt do
      {:error, {:reversed_range, %{from: from, to: to}}}
    else
      :ok
    end
  end

  # A bare scalar on a range facet is a range of one: one day for
  # `:date_range`, the whole UTC day for `:datetime_range` (so
  # `created:2026-07-01` means the day, not the instant midnight).
  defp cast_bare_scalar_range(facet, raw, _operator, opts) do
    with {:ok, value} <- cast_scalar(facet, Facet.scalar(facet), raw, opts) do
      {:ok, :between, %Range{from: value, to: expand_upper(facet, value, raw)}}
    end
  end

  # A date typed into a datetime range covers that whole UTC day. Anything
  # already carrying a time, and every non-datetime range, is left alone.
  defp expand_upper(%Facet{type: :datetime_range}, %DateTime{} = value, raw) do
    if date_only?(raw),
      do: %{value | hour: 23, minute: 59, second: 59, microsecond: {999_999, 6}},
      else: value
  end

  defp expand_upper(_facet, value, _raw), do: value

  defp date_only?(raw), do: Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, raw)

  # -- Lists -------------------------------------------------------------

  # A single element with no comma keeps the scalar operators, so every
  # pre-Spec-018 parse of a `multiple?: true` facet is unchanged.
  defp cast_list(facet, raw, operator, opts) do
    case split_list(raw) do
      [single] ->
        with {:ok, value} <- cast_scalar(facet, facet.type, single, opts) do
          {:ok, operator, value}
        end

      elements ->
        cast_list_elements(facet, elements, operator, opts)
    end
  end

  defp split_list(raw), do: String.split(raw, ",")

  defp cast_list_elements(facet, elements, operator, opts) do
    with :ok <- reject_empty_elements(elements),
         {:ok, values} <- cast_each(facet, elements, opts) do
      {:ok, list_operator(operator), values}
    end
  end

  defp reject_empty_elements(elements) do
    if Enum.any?(elements, &(String.trim(&1) == "")) do
      {:error, {:incomplete_list, %{value: Enum.join(elements, ",")}}}
    else
      :ok
    end
  end

  defp cast_each(facet, elements, opts) do
    Enum.reduce_while(elements, {:ok, []}, fn element, {:ok, acc} ->
      case cast_scalar(facet, facet.type, element, opts) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_operator(:neq), do: :not_in
  defp list_operator(:not_in), do: :not_in
  defp list_operator(_operator), do: :in

  # -- Scalars -----------------------------------------------------------

  defp cast_scalar(_facet, :string, raw, _opts), do: {:ok, raw}

  defp cast_scalar(_facet, :integer, raw, _opts) do
    case Integer.parse(raw) do
      {int, ""} -> {:ok, int}
      _ -> {:error, {:bad_integer, %{value: raw}}}
    end
  end

  defp cast_scalar(_facet, :float, raw, _opts) do
    case parse_float(raw) do
      {:ok, float} -> {:ok, float}
      :error -> {:error, {:bad_float, %{value: raw}}}
    end
  end

  defp cast_scalar(_facet, :boolean, raw, _opts) do
    case String.downcase(raw) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, {:bad_boolean, %{value: raw}}}
    end
  end

  defp cast_scalar(_facet, :date, raw, opts) do
    case Date.from_iso8601(raw) do
      {:ok, date} -> {:ok, date}
      _ -> relative_or_named_date(raw, opts)
    end
  end

  defp cast_scalar(_facet, :datetime, raw, opts) do
    cast_datetime(raw, opts)
  end

  defp cast_scalar(_facet, :duration, raw, _opts), do: cast_duration(raw)

  defp cast_scalar(facet, :enum, raw, _opts) do
    values = facet.values || []

    Enum.find_value(values, {:error, {:not_in_values, %{value: raw, values: values}}}, fn value ->
      Atom.to_string(value) == raw and {:ok, value}
    end)
  end

  defp cast_scalar(_facet, nil, raw, _opts), do: {:ok, raw}

  # `Float.parse/1` is *not* total: it delegates to `:erlang.binary_to_float`,
  # which raises `ArgumentError` when the digits overflow a float (400 nines,
  # say). Since every facet value is arbitrary user input, that has to become
  # an error tuple rather than a crash — casting never raises, for any input.
  defp parse_float(raw) do
    case Float.parse(raw) do
      {float, ""} -> {:ok, float}
      _ -> parse_integer_as_float(raw)
    end
  rescue
    ArgumentError -> :error
  end

  defp parse_integer_as_float(raw) do
    case Integer.parse(raw) do
      {int, ""} -> {:ok, int * 1.0}
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp cast_datetime(raw, opts) do
    case DateTime.from_iso8601(raw) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      _ ->
        with {:ok, date} <- date_for_datetime(raw, opts) do
          {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}
        end
    end
  end

  defp date_for_datetime(raw, opts) do
    case Date.from_iso8601(raw) do
      {:ok, date} ->
        {:ok, date}

      _ ->
        case relative_or_named_date(raw, opts) do
          {:ok, date} -> {:ok, date}
          {:error, _reason} -> {:error, {:bad_datetime, %{value: raw}}}
        end
    end
  end

  # `7d`/`2w` are offsets *back* from the reference date — "in the last 7
  # days" is what a filter means by `after:7d`. Months and years use
  # calendar arithmetic rather than 30/365-day approximations.
  defp relative_or_named_date(raw, opts) do
    today = reference_date(opts)

    case raw do
      "today" ->
        {:ok, today}

      "yesterday" ->
        {:ok, Date.add(today, -1)}

      _ ->
        relative_date(raw, today)
    end
  end

  defp relative_date(raw, today) do
    case Regex.run(~r/^(\d+)([dwmy])$/, raw) do
      [_, amount, unit] when unit in ["d", "w"] ->
        {:ok, Date.add(today, -(String.to_integer(amount) * Map.fetch!(@relative_date_units, unit)))}

      [_, amount, "m"] ->
        {:ok, shift_months(today, -String.to_integer(amount))}

      [_, amount, "y"] ->
        {:ok, shift_months(today, -(String.to_integer(amount) * 12))}

      nil ->
        {:error, {:bad_date, %{value: raw}}}
    end
  end

  defp shift_months(date, months) do
    total = date.year * 12 + (date.month - 1) + months
    year = div(total, 12)
    month = Integer.mod(total, 12) + 1
    day = min(date.day, Date.days_in_month(%{date | year: year, month: month, day: 1}))

    %{date | year: year, month: month, day: day}
  end

  # `2h30m` is a sum of unit-tagged components, each unit used at most once
  # and in descending order — `30m2h` and `2h2h` are rejected rather than
  # quietly accepted, since either is more likely a typo than an intent.
  defp cast_duration(raw) do
    with [_ | _] = parts <- Regex.scan(~r/(\d+)([smhd])/, raw),
         true <- rebuild(parts) == raw,
         true <- units_descending?(parts) do
      {:ok,
       Enum.reduce(parts, 0, fn [_, amount, unit], acc ->
         acc + String.to_integer(amount) * @duration_units[unit]
       end)}
    else
      _ -> {:error, {:bad_duration, %{value: raw}}}
    end
  end

  defp rebuild(parts), do: Enum.map_join(parts, fn [whole, _amount, _unit] -> whole end)

  defp units_descending?(parts) do
    weights = Enum.map(parts, fn [_, _amount, unit] -> @duration_units[unit] end)

    weights == Enum.sort(weights, :desc) and weights == Enum.uniq(weights)
  end

  # -- Bounds and custom validation ---------------------------------------

  defp check_bounds(%Facet{bounds: nil}, _value), do: :ok

  defp check_bounds(%Facet{bounds: bounds}, %Range{from: from, to: to}) do
    with :ok <- check_bounds_value(bounds, from) do
      check_bounds_value(bounds, to)
    end
  end

  defp check_bounds(%Facet{bounds: bounds}, value), do: check_bounds_value(bounds, value)

  defp check_bounds_value(_bounds, nil), do: :ok

  defp check_bounds_value(bounds, value) when is_number(value) do
    min = Map.get(bounds, :min)
    max = Map.get(bounds, :max)

    if (min && value < min) || (max && value > max) do
      {:error, {:out_of_bounds, %{min: min, max: max, value: value}}}
    else
      :ok
    end
  end

  defp check_bounds_value(_bounds, _value), do: :ok

  defp run_custom_validator(%Facet{validate: nil}, _value), do: :ok

  defp run_custom_validator(%Facet{validate: validate}, value) when is_function(validate, 1) do
    case validate.(value) do
      :ok ->
        :ok

      {:error, {reason, params}} when is_atom(reason) and is_map(params) ->
        {:error, {reason, params}}

      {:error, message} when is_binary(message) ->
        {:error, {:custom, %{message: message}}}
    end
  end

  # -- Shared helpers ------------------------------------------------------

  defp compare(%Date{} = from, %Date{} = to), do: Date.compare(from, to)
  defp compare(%DateTime{} = from, %DateTime{} = to), do: DateTime.compare(from, to)

  defp compare(from, to) when is_number(from) and is_number(to) do
    cond do
      from > to -> :gt
      from < to -> :lt
      true -> :eq
    end
  end

  defp compare(_from, _to), do: :eq

  defp reference_date(opts), do: Keyword.get(opts, :today) || Date.utc_today()
  defp first_day_of_week(opts), do: Keyword.get(opts, :first_day_of_week) || 1
end
