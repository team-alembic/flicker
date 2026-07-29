if Code.ensure_loaded?(Ash) and Code.ensure_loaded?(Cinder) do
  defmodule Flicker.CinderInteropTest do
    @moduledoc """
    Covers [Spec 009](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md)
    Levels 1 and 2: `Flicker.search` narrowing a `Cinder.collection` over
    the same resource via `Flicker.Integrations.Cinder`, actor-scoped end
    to end, with URL state round-tripping through the adapter's namespaced
    `flicker_q` param. Drives `Dev.Live.CinderInterop` directly — the
    exact playground LiveView the guide quotes — so neither recipe can
    rot.

    Seed indices used below (see `Dev.Music.seed!/0`'s deterministic
    naming/status/label derivation): "Casey Cassidy" (index 0, public,
    `monthly_listeners: 12_345`) and "Jordan Rivers" (index 12, public,
    `monthly_listeners: 160_485`) are both visible to the fixed public
    actor (`%{label: nil}`) this page reads under; "Alex Cassidy" (index 1,
    `label: "indie"`) never reaches the table under that actor.

    Typing now also patches the URL (the Level 2 adapter's `push_patch/4`),
    and every patch re-runs `handle_params/3` → a fresh Cinder reload —
    a second async hop after `type_search/3`'s own `render_async` await.
    Table assertions therefore pass `timeout:` so PhoenixTest polls
    through that hop instead of racing it.
    """

    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers
    import Phoenix.LiveViewTest, only: [render_async: 2]

    alias Flicker.Integrations.Cinder, as: FlickerCinder

    @moduletag :ash

    @await 2_000

    # Cinder's own table load runs in a `start_async` task on connect,
    # separate from Flicker's search task — wait for it too before the
    # first assertion against table contents.
    defp await_table(session) do
      render_async(session.view, @await)
      session
    end

    test "typing facet syntax narrows the Cinder collection live", %{conn: conn} do
      session = conn |> visit("/cinder-interop") |> await_table()

      assert_has(session, "td", text: "Casey Cassidy")
      assert_has(session, "td", text: "Jordan Rivers")

      session = type_search(session, "artist-search-input", "monthly_listeners>=100000")

      refute_has(session, "td", text: "Casey Cassidy", timeout: @await)
      assert_has(session, "td", text: "Jordan Rivers", timeout: @await)
    end

    test "clearing the search restores the unfiltered collection", %{conn: conn} do
      session =
        conn
        |> visit("/cinder-interop")
        |> await_table()
        |> type_search("artist-search-input", "monthly_listeners>=100000")

      refute_has(session, "td", text: "Casey Cassidy", timeout: @await)

      session = type_search(session, "artist-search-input", "")

      assert_has(session, "td", text: "Casey Cassidy", timeout: @await)
      assert_has(session, "td", text: "Jordan Rivers", timeout: @await)
    end

    test "the composed query is actor-scoped end to end", %{conn: conn} do
      session = conn |> visit("/cinder-interop") |> await_table()

      session = type_search(session, "artist-search-input", "Cassidy")

      assert_has(session, "td", text: "Casey Cassidy", timeout: @await)
      refute_has(session, "td", text: "Alex Cassidy", timeout: @await)
    end

    test "free-text search filters the Cinder table", %{conn: conn} do
      session = conn |> visit("/cinder-interop") |> await_table()

      assert_has(session, "td", text: "Casey Cassidy")
      assert_has(session, "td", text: "Jordan Rivers")

      session = type_search(session, "artist-search-input", "Casey")

      assert_has(session, "td", text: "Casey Cassidy", timeout: @await)
      refute_has(session, "td", text: "Jordan Rivers", timeout: @await)
    end

    describe "URL state (the Level 2 adapter)" do
      test "typing pushes the raw input under the namespaced flicker_q param", %{conn: conn} do
        conn
        |> visit("/cinder-interop")
        |> await_table()
        |> type_search("artist-search-input", ~s(status:active tier:"legendary"))
        |> assert_path("/cinder-interop",
          query_params: %{"flicker_q" => ~s(status:active tier:"legendary")},
          timeout: @await
        )
      end

      test "clearing the search removes the param from the URL entirely", %{conn: conn} do
        conn
        |> visit("/cinder-interop")
        |> await_table()
        |> type_search("artist-search-input", "status:active")
        |> assert_path("/cinder-interop",
          query_params: %{"flicker_q" => "status:active"},
          timeout: @await
        )
        |> type_search("artist-search-input", "")
        |> assert_path("/cinder-interop", query_params: %{}, timeout: @await)
      end

      test "visiting a shared URL restores the narrowed table and its facet pill", %{conn: conn} do
        session =
          conn
          |> visit("/cinder-interop?flicker_q=" <> URI.encode_www_form("monthly_listeners>=100000"))
          |> await_table()

        # Spec 012: the restored facet lands as a pill (not raw text in the
        # input); the narrowed table is unchanged.
        #
        # The number is rendered through `Flicker.Facet.Format` (ADR-013), so
        # with `localize` present it is CLDR-grouped ("100,000") and without it
        # plain ("100000") — both are correct, and asserting one would fail the
        # opposite CI leg.
        expected = if Flicker.Facet.Format.localized?(), do: "100,000", else: "100000"

        assert_has(session, "[role='listitem']", text: expected)
        assert_has(session, "input#artist-search-input[value='']")

        refute_has(session, "td", text: "Casey Cassidy", timeout: @await)
        assert_has(session, "td", text: "Jordan Rivers", timeout: @await)
      end

      test "a Flicker patch preserves Cinder's own sort param alongside flicker_q", %{conn: conn} do
        conn
        |> visit("/cinder-interop?sort=-monthly_listeners")
        |> await_table()
        |> type_search("artist-search-input", "status:active")
        |> assert_path("/cinder-interop",
          query_params: %{"sort" => "-monthly_listeners", "flicker_q" => "status:active"},
          timeout: @await
        )
      end

      test "a shared URL with quoted values and unicode restores as a pill plus verbatim free text", %{conn: conn} do
        input = ~s(worker:"São Paulo" tier:legendary)

        session =
          conn
          |> visit("/cinder-interop?flicker_q=" <> URI.encode_www_form(input))
          |> await_table()

        # Spec 012: the known `tier` facet lifts into a pill; `worker` is not a
        # facet on this page, so it stays as free text in the input, quoting
        # and unicode preserved verbatim.
        assert_has(session, "[role='listitem']", text: "Legendary")
        assert_has(session, ~s(input#artist-search-input[value='worker:"São Paulo"']))
      end
    end

    describe "double-filter convention" do
      test "the playground page's facets and Cinder's filter-managed fields never overlap" do
        assert FlickerCinder.overlapping_fields(
                 Dev.Live.CinderInterop.facet_keys(),
                 Dev.Live.CinderInterop.cinder_filter_fields()
               ) == []
      end
    end
  end
end
