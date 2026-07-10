if Code.ensure_loaded?(Ash) and Code.ensure_loaded?(Cinder) do
  defmodule Flicker.CinderInteropTest do
    @moduledoc """
    Covers [Spec 009](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md)
    Level 1: `Flicker.search` narrowing a `Cinder.collection` over the same
    resource via query composition, actor-scoped end to end. Drives
    `Dev.Live.CinderInterop` directly — the exact playground LiveView the
    guide quotes — so the recipe can't rot.

    Seed indices used below (see `Dev.Music.seed!/0`'s deterministic
    naming/status/label derivation): "Casey Cassidy" (index 0, public,
    `monthly_listeners: 12_345`) and "Jordan Rivers" (index 12, public,
    `monthly_listeners: 160_485`) are both visible to the public actor;
    "Alex Cassidy" (index 1, `label: "indie"`) is only visible once the
    actor toggle switches to the indie label.
    """

    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers
    import Phoenix.LiveViewTest, only: [render_async: 1]

    @moduletag :ash

    # Cinder's own table load runs in a `start_async` task on connect,
    # separate from Flicker's search task — wait for it too before the
    # first assertion against table contents.
    defp await_table(session) do
      render_async(session.view)
      session
    end

    test "typing facet syntax narrows the Cinder collection live", %{conn: conn} do
      session = conn |> visit("/cinder-interop") |> await_table()

      assert_has(session, "td", text: "Casey Cassidy")
      assert_has(session, "td", text: "Jordan Rivers")

      session = type_search(session, "artist-search-input", "monthly_listeners>=100000")

      refute_has(session, "td", text: "Casey Cassidy")
      assert_has(session, "td", text: "Jordan Rivers")
    end

    test "clearing the search restores the unfiltered collection", %{conn: conn} do
      session =
        conn
        |> visit("/cinder-interop")
        |> await_table()
        |> type_search("artist-search-input", "monthly_listeners>=100000")

      refute_has(session, "td", text: "Casey Cassidy")

      session = type_search(session, "artist-search-input", "")

      assert_has(session, "td", text: "Casey Cassidy")
      assert_has(session, "td", text: "Jordan Rivers")
    end

    test "the composed query is actor-scoped end to end", %{conn: conn} do
      session = conn |> visit("/cinder-interop") |> await_table()

      refute_has(session, "td", text: "Alex Cassidy")

      session = click_button(session, "Indie label")

      assert_has(session, "td", text: "Alex Cassidy")

      session = type_search(session, "artist-search-input", "monthly_listeners>=100000")

      refute_has(session, "td", text: "Alex Cassidy")
      assert_has(session, "td", text: "Casey Rivers")
    end
  end
end
