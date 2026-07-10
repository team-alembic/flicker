defmodule Dev.Endpoint do
  @moduledoc """
  The dev playground's Phoenix endpoint (Spec 005) — Bandit-served, started
  only by `Dev.Application` (the `:dev`-only OTP application callback).

  Configured in `config/config.exs` under the `config_env() == :dev` guard;
  never started in `:test` (`Dev.Application` isn't wired as the `mod`
  callback there) and excluded from the Hex package (`dev/` isn't in
  `package.files`).
  """

  use Phoenix.Endpoint, otp_app: :flicker

  @session_options [
    store: :cookie,
    key: "_flicker_dev_key",
    signing_salt: "flicker-dev-salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Session, @session_options)
  plug(Dev.Router)
end
