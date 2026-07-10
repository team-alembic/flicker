defmodule Flicker.SelectKeyboardTest do
  @moduledoc """
  Covers the keyboard map's server-side behaviours (Spec 001) — the parts
  reachable without simulating real key events, i.e. the events the JS hook
  pushes to the server: `escape`'s two-stage close-then-clear, and the
  `connected?/1` gating on interactive controls before the socket joins.

  Arrow-key highlight movement and `Enter`-clicks-the-highlighted-option are
  pure client-side JS (see the colocated hook in
  `Flicker.Components.Select`) — not exercised here (PhoenixTest doesn't run
  JavaScript); they're a candidate for browser-driven coverage later.
  """

  use Flicker.Test.ConnCase, async: true

  import Flicker.Test.Helpers

  defp visit_controlled(conn) do
    conn
    |> Plug.Test.init_test_session(%{"mode" => "controlled"})
    |> visit("/")
  end

  test "escape closes the listbox and keeps the typed text" do
    session =
      build_conn()
      |> visit_controlled()
      |> type_search("picker-input", "cas")

    assert_has(session, "#picker-listbox")

    html =
      session.view
      |> Phoenix.LiveViewTest.element("#picker")
      |> Phoenix.LiveViewTest.render_hook("escape", %{})

    refute html =~ "<ul"
    assert html =~ ~s(aria-expanded="false")
    assert html =~ ~s(value="cas")
  end

  test "a second escape (closed, text present) clears the input" do
    session =
      build_conn()
      |> visit_controlled()
      |> type_search("picker-input", "cas")

    element = Phoenix.LiveViewTest.element(session.view, "#picker")
    Phoenix.LiveViewTest.render_hook(element, "escape", %{})
    html = Phoenix.LiveViewTest.render_hook(element, "escape", %{})

    assert html =~ ~s(value="")
  end

  test "interactive controls are disabled before the socket connects" do
    conn = Plug.Test.init_test_session(build_conn(), %{"mode" => "controlled"})
    html = conn |> Phoenix.ConnTest.get("/") |> Phoenix.ConnTest.html_response(200)

    assert html =~ ~s(id="picker-input")
    assert html =~ "disabled"
  end
end
