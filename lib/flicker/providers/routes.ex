defmodule Flicker.Providers.Routes do
  @moduledoc """
  A `Flicker.Provider` that derives navigable destinations from a host's own
  `Phoenix.Router` ([Spec 011](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-011-router-navigation-provider.md)).

  This is the other half of the ⌘K experience: a palette that can take you to a
  *screen*, not only to a record, with one line of config and nothing to keep in
  sync when a route changes.

      <Flicker.palette source={{Flicker.Providers.Routes, router: MyAppWeb.Router}} />

  Results carry `meta.href`, which is Spec 008's navigate-on-select convention,
  and `group: "Pages"` so they read as a section when federated alongside
  records.

  ## Authorisation: this provider is not policy-scoped

  **A router knows paths, not permissions.** Every other Flicker provider reads
  through `actor:` and Ash policies
  ([ADR-004](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-004-authorization-via-actor-and-policies.md)),
  and this one structurally cannot: a route is a compile-time fact with nothing
  to authorise against. It lists what it is given.

  That makes the default deliberately conservative — only `GET`/`live` routes,
  no parameterised paths, and framework mounts excluded — and it makes
  `:visible?` the mechanism that matters. Pass `visible?: fn route, actor ->
  boolean end` to gate destinations for the current actor, and treat any
  sensitive path as needing that gate rather than assuming the search hid it.
  A palette entry is not an authorisation boundary in any case: it reveals that
  a path exists, and the page behind it must still refuse.

  ## Options

    * `:router` — required, the `Phoenix.Router` module to introspect.
    * `:only` — path prefixes to include (list of strings). Everything else is
      dropped.
    * `:except` — path prefixes to exclude. Applied after `:only`.
    * `:visible?` — `fn route, actor -> boolean end`, the authorisation hook
      described above.
    * `:label` — `fn route -> String.t() end`, overriding the derived label.
    * `:group` — the group label. Defaults to `"Pages"`; `nil` opts out of
      grouping.
    * `:extra` — additional destinations the router can't supply, as
      `[%{label: ..., href: ...}]`. This is where a parameterised favourite
      ("My profile" → `/users/42`) belongs.

  ## Label derivation

  Dumb but predictable: path segments are humanised and joined with `·`, so
  `/user-settings/billing` becomes "User settings · Billing" and `/` becomes
  "Home". Where that reads badly, `:label` overrides it — the derivation never
  tries to be clever, because a surprising label is worse than a plain one.
  """

  @behaviour Flicker.Provider

  alias Flicker.{Query, Result}

  @default_group "Pages"

  @impl true
  @doc """
  Returns routes whose label matches `query.text`, case-insensitively.

  `query.facets` is ignored: a route has no attributes to facet on. Free text is
  matched against the derived (or overridden) label, not the raw path, since the
  label is what the user sees.
  """
  @spec search(Query.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def search(%Query{text: text}, opts) do
    results =
      opts
      |> destinations()
      |> filter_by_text(text)
      |> limit(Keyword.get(opts, :limit))

    {:ok, results}
  end

  @impl true
  @doc """
  Resolves hrefs back to results, so a palette restoring state from a URL shows
  the destination's label rather than its path.

  Values not present are simply absent, as
  [ADR-003](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-003-fetch-takes-a-list.md)
  requires of every provider.
  """
  @spec fetch([term()], keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def fetch(values, opts) do
    wanted = MapSet.new(values, &to_string/1)

    {:ok, opts |> destinations() |> Enum.filter(&MapSet.member?(wanted, to_string(&1.value)))}
  end

  @doc """
  Every destination this provider would offer, unfiltered by text.

  Exposed so a host can inspect what a given configuration actually exposes —
  worth doing once for anything sensitive, given the authorisation caveat above.

  ## Examples

      iex> Flicker.Providers.Routes.destinations(router: Flicker.Test.Router)
      ...> |> Enum.all?(&(&1.meta.href =~ "/"))
      true
  """
  @spec destinations(keyword()) :: [Result.t()]
  def destinations(opts) do
    router = Keyword.fetch!(opts, :router)
    group = Keyword.get(opts, :group, @default_group)

    router
    |> Phoenix.Router.routes()
    |> Enum.filter(&(navigable?(&1) and included?(&1, opts) and visible?(&1, opts)))
    |> Enum.uniq_by(& &1.path)
    |> Enum.map(&to_result(&1, opts, group))
    |> Enum.concat(extra_results(opts, group))
  end

  # Only routes you can actually navigate to: a GET (or a `live` route, which
  # Phoenix also records as GET), and nothing parameterised — `/artists/:id` has
  # no destination without an id, and inventing one would 404.
  defp navigable?(%{verb: :get, path: path}), do: not String.contains?(path, ":") and not String.contains?(path, "*")

  defp navigable?(_route), do: false

  defp included?(route, opts) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, framework_paths())

    matches_only?(route.path, only) and not matches_any?(route.path, except)
  end

  defp matches_only?(_path, nil), do: true
  defp matches_only?(path, only), do: matches_any?(path, only)

  defp matches_any?(path, prefixes), do: Enum.any?(prefixes, &String.starts_with?(path, &1))

  # Excluded by default: mounts a user never means to navigate to from a
  # palette. A host that *does* want them passes its own `:except`.
  defp framework_paths, do: ["/dev/", "/phoenix/", "/live_dashboard"]

  defp visible?(route, opts) do
    case Keyword.get(opts, :visible?) do
      nil -> true
      fun when is_function(fun, 2) -> fun.(route, Keyword.get(opts, :actor))
    end
  end

  defp to_result(route, opts, group) do
    %Result{
      value: route.path,
      label: label_for(route, opts),
      meta: %{href: route.path},
      group: group
    }
  end

  defp label_for(route, opts) do
    case Keyword.get(opts, :label) do
      fun when is_function(fun, 1) -> fun.(route)
      _nil -> derive_label(route.path)
    end
  end

  @doc """
  The label derived from a path — humanised segments joined with `·`.

  ## Examples

      iex> Flicker.Providers.Routes.derive_label("/")
      "Home"

      iex> Flicker.Providers.Routes.derive_label("/user-settings/billing")
      "User settings · Billing"

      iex> Flicker.Providers.Routes.derive_label("/artists")
      "Artists"
  """
  @spec derive_label(String.t()) :: String.t()
  def derive_label("/"), do: "Home"

  def derive_label(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.map_join(" · ", &humanise/1)
  end

  defp humanise(segment) do
    segment
    |> String.replace(["-", "_"], " ")
    |> then(fn
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
      other -> other
    end)
  end

  defp extra_results(opts, group) do
    opts
    |> Keyword.get(:extra, [])
    |> Enum.map(fn entry ->
      %Result{
        value: entry.href,
        label: entry.label,
        meta: %{href: entry.href},
        group: Map.get(entry, :group, group)
      }
    end)
  end

  defp filter_by_text(results, text) when text in [nil, ""], do: results

  defp filter_by_text(results, text) do
    downcased = String.downcase(text)

    Enum.filter(results, &String.contains?(String.downcase(&1.label), downcased))
  end

  defp limit(results, nil), do: results
  defp limit(results, limit), do: Enum.take(results, limit)
end
