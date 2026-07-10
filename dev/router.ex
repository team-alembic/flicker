defmodule Dev.Router do
  @moduledoc """
  Routes for the dev playground (Spec 005) — one path per capability page.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_root_layout, html: {Dev.Layouts, :root})
  end

  scope "/" do
    pipe_through(:browser)

    live("/", Dev.Live.Home)
    live("/single-select", Dev.Live.SingleSelect)
    live("/multi-select", Dev.Live.MultiSelect)
    live("/static-provider", Dev.Live.StaticProvider)
    live("/themes", Dev.Live.ThemeShowcase)
    live("/edge-states", Dev.Live.EdgeStates)
    live("/keyboard-activation", Dev.Live.KeyboardActivation)
  end
end
