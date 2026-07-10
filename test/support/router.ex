defmodule Flicker.Test.Router do
  @moduledoc """
  The test-support router — routes the single host page PhoenixTest drives.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)

    live("/", Flicker.Test.HostLive)

    if Code.ensure_loaded?(Ash) do
      live("/ash", Flicker.Test.AshHostLive)
    end

    if Code.ensure_loaded?(AshPhoenix.Form) do
      live("/ash-phoenix-form", Flicker.Test.AshPhoenixFormHostLive)
    end
  end
end
