defmodule Flicker.PaletteTest do
  @moduledoc """
  Covers `Flicker.palette/1` (Spec 008): the controlled `open`/`on_close`
  API, `role="dialog"`/`aria-modal` semantics, contiguous group-header
  rendering (and its groupless no-op), navigate-on-select via
  `meta.href`, and the raw `on_select` message.

  Entirely backed by `Flicker.Providers.Static` (`Flicker.Test.PaletteHostLive`)
  and deliberately not `@moduletag :ash` — proving the palette stands
  alone on a pure-Elixir provider, same as the plain select (ADR-006).

  Client-side behaviour not reachable from ExUnit (focus trap, focus
  restore, scroll lock, the `mod+k` open/close toggle actually firing on a
  real `KeyboardEvent`) is covered instead by manual/browser testing
  against the dev playground's `/palette` page, mirroring
  `Flicker.SelectKeyboardActivationTest`'s approach for Spec 006.
  """

  use Flicker.Test.ConnCase, async: true

  import Flicker.Test.Helpers
  import Phoenix.LiveViewTest

  defp visit_palette(conn, session_overrides \\ %{}) do
    conn = Plug.Test.init_test_session(conn, session_overrides)
    visit(conn, "/palette")
  end

  # Opens the palette, then types "ca" into the nested search — every
  # fixture result contains "ca" (`Flicker.Providers.Static`'s search
  # matches `:label`/`:sublabel` case-insensitively), so this reveals the
  # full fixture list. Typing (not just focusing) is what actually opens
  # the listbox in this headless test environment — mirrors every other
  # select test in this suite (`Flicker.Test.Helpers.type_search/3`).
  defp open_and_search(session) do
    session
    |> click_button("Open palette")
    |> type_search("cmdk-select-input", "ca")
  end

  describe "controlled open/close" do
    test "the test helper opens a palette", %{conn: conn} do
      session = conn |> visit_palette() |> Flicker.Test.open_palette("cmdk")

      assert_has(session, "[role='dialog'][aria-modal='true']")
    end

    test "does not require host notification tags for navigation-only palettes", %{conn: conn} do
      session = conn |> visit_palette(%{"silent" => true, "open" => true}) |> click_button("Close")

      refute_has(session, "[role='dialog']")
    end

    test "renders closed by default: no dialog", %{conn: conn} do
      session = visit_palette(conn)
      refute_has(session, "[role='dialog']")
    end

    test "the trigger button opens it via the open/on_close controlled API", %{conn: conn} do
      session = conn |> visit_palette() |> click_button("Open palette")

      assert_has(session, "[role='dialog'][aria-modal='true']")
    end

    test "closing sends on_close and the dialog disappears", %{conn: conn} do
      session = conn |> visit_palette() |> click_button("Open palette")
      assert_has(session, "[role='dialog']")

      session = click_button(session, "Close")

      refute_has(session, "[role='dialog']")
      assert_has(session, "#close-count", text: "1")
    end

    test "the wrapper carries the keyboard-activation chord even while closed", %{conn: conn} do
      session = visit_palette(conn)
      assert_has(session, "#cmdk[data-activate-with-keyboard='mod+k']")
    end
  end

  describe "selection" do
    test "selecting a result fires the raw on_select message", %{conn: conn} do
      session = conn |> visit_palette() |> open_and_search()

      session = click_button(session, "Casey Cassidy")

      assert_has(session, "#palette-selection", text: "Casey Cassidy")
    end

    test "selecting closes the overlay (host sets open false from on_select)", %{conn: conn} do
      session = conn |> visit_palette() |> open_and_search()

      session = click_button(session, "Casey Cassidy")

      refute_has(session, "[role='dialog']")
    end

    test "selecting a result with meta.href push_navigates there", %{conn: conn} do
      session = conn |> visit_palette() |> open_and_search()

      result =
        session.view
        |> element("button", "Cassidy Records")
        |> render_click()

      assert {:error, {:live_redirect, %{to: "/records/label/4"}}} = result
    end
  end

  describe "grouped results" do
    test "contiguous group headers render in provider order", %{conn: conn} do
      session = conn |> visit_palette() |> open_and_search()

      html = render(session.view)

      artists_index = :binary.match(html, "Artists") |> elem(0)
      albums_index = :binary.match(html, "Albums") |> elem(0)
      labels_index = :binary.match(html, "Labels") |> elem(0)

      assert artists_index < albums_index
      assert albums_index < labels_index

      # Contiguous: exactly one header per group, not one per result.
      assert html |> String.split("Albums") |> length() == 2
    end

    test "a groupless provider renders with no group headers at all", %{conn: conn} do
      session = conn |> visit_palette(%{"grouped" => false}) |> open_and_search()

      refute_has(session, ".flicker-group-header")
      assert_has(session, "[role='option']", text: "Casey Cassidy")
      assert_has(session, "[role='option']", text: "Cassidy Records")
    end
  end
end
