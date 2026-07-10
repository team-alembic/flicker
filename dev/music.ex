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

  @doc """
  Seeds the domain with deterministic data: ~50 artists (varying status,
  formation date, monthly listeners, label, and genre) and a handful of
  albums per artist.

  Deterministic — no randomness — so the same call always produces the
  same records, and searches like "cas" reliably match the same artist
  (`"Casey Cassidy"`, seed index 0). Safe to call repeatedly: each calling
  process gets its own private ETS table (see the moduledoc), so a fresh
  call from a fresh test process starts from empty.

  Returns `%{genres: [Dev.Music.Genre.t()], artists: [Dev.Music.Artist.t()]}`.
  """
  @spec seed!() :: %{genres: [struct()], artists: [struct()]}
  def seed! do
    genres = Enum.map(@genre_names, &create_genre!/1)
    artists = Enum.map(0..49, &create_artist!(&1, genres))

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

  defp artist_name(index) do
    first = Enum.at(@first_names, rem(index, length(@first_names)))
    last = Enum.at(@last_names, div(index, length(@first_names)))
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
