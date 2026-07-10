defmodule Flicker.SelectKeyboardActivationTest do
  @moduledoc """
  Covers `activate_with_keyboard`'s (Spec 006) server-side surface: attr
  validation and the markup the colocated hook depends on
  (`data-activate-with-keyboard`, the `<kbd>` hint, `aria-keyshortcuts`).

  Everything else in Spec 006's acceptance criteria is client-side JS and
  not reachable from ExUnit (PhoenixTest doesn't run JavaScript) —
  covered instead by manual/browser testing against the dev playground's
  `/keyboard-activation` page:

    * the chord actually matching a live `KeyboardEvent` anywhere in the
      document, including while focus is in an unrelated text input;
    * the `mod` alias resolving to Meta on macOS / Ctrl elsewhere;
    * focusing and opening the listbox on match, and toggling it closed
      again when the component is already focused/open;
    * the document keydown listener being added on mount and removed on
      `destroyed` (no activation after the LiveView unmounts);
    * two components claiming the same chord: the console warning and
      that only the first registration ever activates;
    * the kbd hint's text updating to platform-formatted symbols
      (`⌘K` vs `Ctrl+K`) once the hook mounts;
    * inertness before the socket connects (a keypress before then does
      nothing and isn't queued for after connect).
  """

  use Flicker.Test.ConnCase, async: true

  defp visit_with_chord(conn, chord) do
    conn
    |> Plug.Test.init_test_session(%{"mode" => "controlled", "activate_with_keyboard" => chord})
    |> visit("/")
  end

  test "a valid chord renders the kbd hint, aria-keyshortcuts, and the hook's data attribute", %{conn: conn} do
    session = visit_with_chord(conn, "mod+k")

    assert_has(session, "#picker[data-activate-with-keyboard='mod+k']")
    assert_has(session, "#picker-input[aria-keyshortcuts='Meta+K Control+K']")
    assert_has(session, "kbd", text: "Mod+K")
    assert_has(session, "kbd[title='Keyboard shortcut: Mod+K']")
  end

  test "omitting activate_with_keyboard renders no kbd hint or aria-keyshortcuts", %{conn: conn} do
    conn = Plug.Test.init_test_session(conn, %{"mode" => "controlled"})
    html = conn |> Phoenix.ConnTest.get("/") |> Phoenix.ConnTest.html_response(200)

    refute html =~ "<kbd"
    refute html =~ "aria-keyshortcuts"
    refute html =~ "data-activate-with-keyboard"
  end

  test "a bare-key chord raises ArgumentError at render time, not silently", %{conn: conn} do
    conn = Plug.Test.init_test_session(conn, %{"mode" => "controlled", "activate_with_keyboard" => "k"})

    assert_raise ArgumentError, ~r/bare-key/, fn ->
      Phoenix.ConnTest.get(conn, "/")
    end
  end

  test "an unknown modifier raises ArgumentError at render time", %{conn: conn} do
    conn = Plug.Test.init_test_session(conn, %{"mode" => "controlled", "activate_with_keyboard" => "cmd+k"})

    assert_raise ArgumentError, ~r/unknown modifier/, fn ->
      Phoenix.ConnTest.get(conn, "/")
    end
  end
end
