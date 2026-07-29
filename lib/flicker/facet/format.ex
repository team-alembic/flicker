defmodule Flicker.Facet.Format do
  @moduledoc """
  Display formatting for facet values ([Spec 018](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-018-rich-facet-types.md)) —
  the one module allowed to call `Localize.*`.

  Token text is locale-invariant and localisation is a display layer
  ([ADR-013](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-013-canonical-tokens-localised-display.md)),
  so every value that reaches a screen passes through here: a range pill's
  interval, a number's grouping, a duration's units, a multi-value list's
  conjunction. Concentrating that in one module means the with-`localize` and
  without-`localize` implementations sit side by side per concern, rather than
  a `Code.ensure_loaded?/1` at every call site.

  `localize` is an optional dependency. Without it every function here falls
  back to ISO 8601 dates, plain digits, and English joins — correct, just not
  localised. With it, CLDR supplies interval formats, number grouping,
  plural-aware durations, and list conjunctions for over 700 locales.

  ## Locale

  Every function takes `:locale` in `opts` rather than reading
  `Localize.get_locale/0` at the point of formatting. `Localize`'s locale is
  process-scoped, and a LiveView component may format inside an async assign
  or a different process than the one that mounted — so the locale travels
  with the call. `nil` (the default) means "whatever the process has", which
  is the right behaviour for a plain synchronous render.
  """

  alias Flicker.Facet
  alias Flicker.Facet.{Preset, Range}

  @localize? Code.ensure_loaded?(Localize)

  @doc """
  Whether CLDR formatting is available — `true` when the optional `localize`
  dependency is present.

  Exposed so tests can assert *which* path they exercised rather than guessing
  from the output.
  """
  @spec localized?() :: boolean()
  def localized?, do: @localize?

  @doc """
  A facet value's display string.

  Dispatches on the shape of the value rather than the facet's type, so a
  hand-built facet with an unexpected value still renders something sensible
  instead of raising.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, value_labels: %{active: "Active"})
      ...> Flicker.Facet.Format.value_label(facet, :active)
      "Active"

      iex> facet = Flicker.Facet.new(key: :length, type: :duration)
      ...> label = Flicker.Facet.Format.value_label(facet, 9000)
      ...> label in ["2h30m", "2 hours and 30 minutes"]
      true

      iex> facet =
      ...>   Flicker.Facet.new(
      ...>     key: :status,
      ...>     type: :enum,
      ...>     multiple?: true,
      ...>     value_labels: %{a: "A", b: "B"}
      ...>   )
      ...>
      ...> Flicker.Facet.Format.value_label(facet, [:a, :b])
      "A and B"

  The duration example above admits two answers on purpose: `2h30m` is the
  fallback, `2 hours and 30 minutes` is CLDR's. Which one you get depends on
  whether the optional `localize` dependency is present, and a doctest can't
  branch on that.
  """
  @spec value_label(Facet.t(), term(), keyword()) :: String.t()
  def value_label(facet, value, opts \\ [])

  def value_label(facet, %Range{} = range, opts), do: range_label(facet, range, opts)

  def value_label(facet, values, opts) when is_list(values) do
    values
    |> Enum.map(&value_label(facet, &1, opts))
    |> join_list(opts)
  end

  def value_label(%Facet{type: :duration}, seconds, opts) when is_integer(seconds) do
    duration(seconds, opts)
  end

  def value_label(_facet, %Date{} = date, opts), do: date(date, opts)
  def value_label(_facet, %DateTime{} = datetime, opts), do: datetime(datetime, opts)
  def value_label(_facet, value, opts) when is_number(value), do: number(value, opts)

  def value_label(facet, value, _opts) when is_atom(value) and not is_nil(value), do: Facet.value_label(facet, value)

  def value_label(_facet, value, _opts), do: to_string(value)

  @doc """
  A range's display string — a preset's own label when the range came from
  one, otherwise the interval.

  A preset renders as what the user chose ("Last 30 days"), not as the dates it
  resolved to, which is the whole reason `Flicker.Facet.Range` carries
  `:preset`.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...>
      ...> range = %Flicker.Facet.Range{
      ...>   from: ~D[2026-06-30],
      ...>   to: ~D[2026-07-29],
      ...>   preset: :last_30_days
      ...> }
      ...>
      ...> Flicker.Facet.Format.range_label(facet, range)
      "Last 30 days"

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.Facet.Format.range_label(facet, %Flicker.Facet.Range{from: 10, to: 50})
      "10 – 50"

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.Facet.Format.range_label(facet, %Flicker.Facet.Range{from: 10, to: nil})
      "10 or more"

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.Facet.Format.range_label(facet, %Flicker.Facet.Range{from: nil, to: 50})
      "up to 50"
  """
  @spec range_label(Facet.t(), Range.t(), keyword()) :: String.t()
  def range_label(facet, range, opts \\ [])

  def range_label(facet, %Range{preset: preset} = range, opts) when not is_nil(preset) do
    case Preset.find_by_id(preset, facet.presets || Preset.builtin()) do
      nil -> interval(facet, range, opts)
      found -> found.label
    end
  end

  def range_label(facet, range, opts), do: interval(facet, range, opts)

  defp interval(facet, %Range{from: nil, to: nil}, _opts), do: Facet.value_label(facet, :any)

  defp interval(facet, %Range{from: from, to: nil}, opts) do
    "#{endpoint(facet, from, opts)} or more"
  end

  defp interval(facet, %Range{from: nil, to: to}, opts) do
    "up to #{endpoint(facet, to, opts)}"
  end

  defp interval(facet, %Range{from: same, to: same}, opts), do: endpoint(facet, same, opts)

  defp interval(facet, %Range{from: from, to: to}, opts) do
    localized_interval(from, to, opts) ||
      "#{endpoint(facet, from, opts)} – #{endpoint(facet, to, opts)}"
  end

  defp endpoint(_facet, %Date{} = value, opts), do: date(value, opts)
  defp endpoint(_facet, %DateTime{} = value, opts), do: datetime(value, opts)
  defp endpoint(_facet, value, opts) when is_number(value), do: number(value, opts)
  defp endpoint(_facet, value, _opts), do: to_string(value)

  # -- The localize boundary ----------------------------------------------
  #
  # Each concern has exactly two implementations, chosen at compile time. The
  # fallbacks are not placeholders: without `localize` they are the shipped
  # behaviour, so they have to read acceptably on their own.

  if @localize? do
    defp date(date, opts) do
      case Localize.Date.to_string(date, locale_opts(opts)) do
        {:ok, formatted} -> formatted
        _error -> Date.to_iso8601(date)
      end
    end

    defp datetime(datetime, opts) do
      case Localize.DateTime.to_string(datetime, locale_opts(opts)) do
        {:ok, formatted} -> formatted
        _error -> DateTime.to_iso8601(datetime)
      end
    end

    defp number(value, opts) do
      case Localize.Number.to_string(value, locale_opts(opts)) do
        {:ok, formatted} -> formatted
        _error -> to_string(value)
      end
    end

    defp join_list(parts, opts) do
      case Localize.List.to_string(parts, locale_opts(opts)) do
        {:ok, formatted} -> formatted
        _error -> fallback_join(parts)
      end
    end

    # CLDR interval formatting collapses the shared parts of two dates
    # ("Jun 18 – Jul 12", "18–24 Jul 2026"), which is the whole reason a range
    # pill is legible. `nil` means "no localised form available", and the
    # caller falls back to two formatted endpoints with a dash.
    defp localized_interval(from, to, opts) do
      case Localize.Interval.to_string(from, to, locale_opts(opts)) do
        {:ok, formatted} -> formatted
        _error -> nil
      end
    rescue
      # Interval formatting is pickier about its arguments than the other
      # entry points (mixed types, unsupported calendars); a display helper
      # must never take a render down over a label.
      _error -> nil
    end

    # `Localize.Duration` has its own struct — Elixir's `Duration` is not
    # accepted — and `new_from_seconds/1` is the constructor that normalises a
    # second count into CLDR's h/m/s components, so 9000 renders as
    # "2 hours, 30 minutes" rather than "9,000 seconds".
    defp duration(seconds, opts) do
      seconds
      |> Localize.Duration.new_from_seconds()
      |> Localize.Duration.to_string(locale_opts(opts))
      |> case do
        {:ok, formatted} -> formatted
        _error -> fallback_duration(seconds)
      end
    rescue
      _error -> fallback_duration(seconds)
    end

    defp locale_opts(opts) do
      case Keyword.get(opts, :locale) do
        nil -> []
        locale -> [locale: locale]
      end
    end
  else
    defp date(date, _opts), do: Date.to_iso8601(date)
    defp datetime(datetime, _opts), do: DateTime.to_iso8601(datetime)
    defp number(value, _opts), do: to_string(value)
    defp join_list(parts, _opts), do: fallback_join(parts)
    defp localized_interval(_from, _to, _opts), do: nil
    defp duration(seconds, _opts), do: fallback_duration(seconds)
  end

  defp fallback_join([]), do: ""
  defp fallback_join([single]), do: single
  defp fallback_join([first, second]), do: "#{first} and #{second}"

  defp fallback_join(parts) do
    {leading, [last]} = Enum.split(parts, -1)

    Enum.join(leading, ", ") <> " and " <> last
  end

  # The same compound form the grammar accepts (`2h30m`), so the fallback
  # display and the typed token agree — a user who sees `2h30m` on a pill can
  # type it back verbatim.
  defp fallback_duration(0), do: "0s"

  defp fallback_duration(seconds) when seconds < 0, do: "-" <> fallback_duration(-seconds)

  defp fallback_duration(seconds) do
    [{86_400, "d"}, {3_600, "h"}, {60, "m"}, {1, "s"}]
    |> Enum.reduce({seconds, []}, fn {size, unit}, {remaining, acc} ->
      case div(remaining, size) do
        0 -> {remaining, acc}
        count -> {rem(remaining, size), [{count, unit} | acc]}
      end
    end)
    |> then(fn {_remaining, acc} -> acc end)
    |> Enum.reverse()
    |> Enum.map_join(fn {count, unit} -> "#{count}#{unit}" end)
  end
end
