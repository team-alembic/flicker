defmodule Dev.Music do
  @moduledoc """
  The seeded music-catalogue domain shared by Spec 004's test harness and
  Spec 005's dev playground.

  `Dev.Music.{Artist, Album, Genre}` run on `Ash.DataLayer.Ets` with
  `private?: true`, so each calling process (each async test) gets its own
  isolated table — `seed!/0` is safe to call once per test, against a fresh
  table every time, with no cross-test bleed and no database.

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
  (`"Casey Cassidy"`, seed index 0). Safe to call repeatedly: each calling
  process gets its own private ETS table (see the moduledoc), so a fresh
  call from a fresh test process starts from empty.

  `count` is an additive parameter for the dev playground's windowed-search
  page ([Spec 010](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-010-windowed-search.md)),
  which needs a population large enough to make scrolling through several
  windows meaningful — every existing caller keeps the default 50.

  Returns `%{genres: [Dev.Music.Genre.t()], artists: [Dev.Music.Artist.t()]}`.
  """
  @spec seed!(pos_integer()) :: %{genres: [struct()], artists: [struct()]}
  def seed!(count \\ @default_artist_count) do
    genres = Enum.map(@genre_names, &create_genre!/1)
    artists = Enum.map(0..(count - 1), &create_artist!(&1, genres))

    %{genres: genres, artists: artists}
  end

  defp create_genre!(name) do
    Ash.create!(Dev.Music.Genre, %{name: name}, authorize?: false)
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
