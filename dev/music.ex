defmodule Dev.Music do
  @moduledoc """
  The seeded music-catalogue domain shared by Spec 004's test harness and
  Spec 005's dev playground.

  `Dev.Music.{Artist, Album, Genre}` run on `Ash.DataLayer.Ets` with
  **shared** (non-private) tables — a `private?: true` table is `:private`
  ETS, readable only by its owner process, which made every playground
  page's search come back empty in a real browser: the select component's
  search runs in a `start_async` task, a different process from the
  LiveView `mount/3` that seeded (Spec 007's browser suite caught this;
  same reasoning as `Flicker.Test.PolicyArtist`). Cross-test isolation
  comes from `seed!/1` being deterministic and idempotent instead: every
  caller converges on the same one seed set, however many async tests call
  it concurrently, with no cross-test bleed and no database.

  `Dev.Music.Artist` is the policy-bearing resource: its `:label` field
  gates visibility by actor (see its moduledoc), so actor-scoping
  assertions are first-class.
  """

  use Ash.Domain

  resources do
    resource(Dev.Music.Genre)
    resource(Dev.Music.Artist)
    resource(Dev.Music.Album)
  end

  @genre_names ["Rock", "Jazz", "Electronic", "Folk", "Hip Hop"]

  @first_names ~w(Casey Alex Jordan Riley Morgan Taylor Avery Quinn Reese Skyler)
  @last_names ~w(Cassidy Rivers Blake Monroe Sawyer Ellis Doyle Frost Lennox Vance)

  @default_artist_count 50

  @doc """
  Seeds the domain with deterministic data: `count` artists (default 50,
  varying status, formation date, monthly listeners, label, and genre) and
  a handful of albums per artist.

  Deterministic — no randomness — so the same call always produces the
  same records, and searches like "cas" reliably match the same artist
  (`"Casey Cassidy"`, seed index 0). Idempotent, and safe to call
  concurrently from async tests (the tables are shared now — see the
  moduledoc): a `:global`-locked critical section seeds only what's
  missing, so every caller converges on the same single seed set instead
  of duplicating it. A larger `count` than what's already seeded tops the
  population up from the next seed index; a smaller one leaves existing
  rows in place and just returns the first `count`.

  `count` is an additive parameter for the dev playground's windowed-search
  page ([Spec 010](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-010-windowed-search.md)),
  which needs a population large enough to make scrolling through several
  windows meaningful — every existing caller keeps the default 50.

  Returns `%{genres: [Dev.Music.Genre.t()], artists: [Dev.Music.Artist.t()]}`
  with `artists` in seed-index order.
  """
  @spec seed!(pos_integer()) :: %{genres: [struct()], artists: [struct()]}
  def seed!(count \\ @default_artist_count) do
    :global.trans({{__MODULE__, :seed}, self()}, fn ->
      genres = ensure_genres!()
      existing = seeded_artists()
      existing_count = length(existing)

      topped_up =
        if existing_count < count do
          Enum.map(existing_count..(count - 1), &create_artist!(&1, genres))
        else
          []
        end

      %{genres: genres, artists: Enum.take(existing ++ topped_up, count)}
    end)
  end

  defp ensure_genres! do
    existing = Map.new(Ash.read!(Dev.Music.Genre, authorize?: false), &{&1.name, &1})

    Enum.map(@genre_names, fn name ->
      existing[name] || Ash.create!(Dev.Music.Genre, %{name: name}, authorize?: false)
    end)
  end

  # Every seeded artist's `formed_on` is `~D[1970-01-01]` + index * 137
  # days — strictly increasing and unique per seed index — so sorting by it
  # recovers seed-index order without storing the index itself. Rows tests
  # create ad hoc (outside `seed!/1`) carry no `formed_on`, so they're
  # excluded here rather than miscounted as seeds.
  defp seeded_artists do
    Dev.Music.Artist
    |> Ash.read!(authorize?: false)
    |> Enum.filter(& &1.formed_on)
    |> Enum.sort_by(& &1.formed_on, Date)
  end

  defp create_artist!(index, genres) do
    artist =
      Ash.create!(
        Dev.Music.Artist,
        %{
          name: artist_name(index),
          status: artist_status(index),
          formed_on: artist_formed_on(index),
          monthly_listeners: artist_monthly_listeners(index),
          label: artist_label(index),
          genre_id: Enum.at(genres, rem(index, length(genres))).id
        },
        authorize?: false
      )

    Enum.each(1..artist_album_count(index), fn album_index ->
      create_album!(artist, index, album_index)
    end)

    artist
  end

  defp create_album!(artist, artist_index, album_index) do
    Ash.create!(
      Dev.Music.Album,
      %{
        title: "#{artist.name}'s Album #{album_index}",
        release_date: Date.add(~D[1990-01-01], artist_index * 137 + album_index * 30),
        track_count: 8 + rem(artist_index + album_index, 10),
        artist_id: artist.id
      },
      authorize?: false
    )
  end

  # Wraps the last-name cursor (rather than growing unbounded, or crashing
  # on `Enum.at/2` returning `nil` past the 10x10 combo space) so `count`
  # can go well past 100 for the windowed-search playground page — names
  # repeat past index 99 (with a distinct status/label/formed_on still
  # distinguishing them), which is fine for a demo population. Existing
  # callers all stay within the first 100 indices, so `"Casey Cassidy"` at
  # index 0 (and every other name a test asserts on) is unaffected.
  defp artist_name(index) do
    first = Enum.at(@first_names, rem(index, length(@first_names)))
    last = Enum.at(@last_names, rem(div(index, length(@first_names)), length(@last_names)))
    "#{first} #{last}"
  end

  defp artist_status(index) do
    case rem(index, 3) do
      0 -> :active
      1 -> :inactive
      2 -> :on_hiatus
    end
  end

  defp artist_formed_on(index), do: Date.add(~D[1970-01-01], index * 137)

  defp artist_monthly_listeners(index), do: (index + 1) * 12_345

  # Roughly a third public (no label), a third "indie", a third "major" —
  # enough spread that toggling the actor visibly changes results.
  defp artist_label(index) do
    case rem(index, 3) do
      0 -> nil
      1 -> "indie"
      2 -> "major"
    end
  end

  defp artist_album_count(index), do: rem(index, 3) + 1
end
