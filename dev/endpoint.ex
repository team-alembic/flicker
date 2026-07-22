defmodule Dev.Endpoint do
  @moduledoc """
  The dev playground's Phoenix endpoint (Spec 005) — Bandit-served, started
  only by `Dev.Application` (the `:dev`-only OTP application callback).

  Configured in `config/config.exs` under the `config_env() == :dev` guard;
  started by `Dev.Application` in `:dev`, and also started directly (over
  real HTTP, a different port) by Spec 007's browser-driven suite in
  `:test` — see `test/support/browser_case.ex`.
  """

  use Phoenix.Endpoint, otp_app: :flicker

  @session_options [
    store: :cookie,
    key: "_flicker_dev_key",
    signing_salt: "flicker-dev-salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket)

  # Serves `Phoenix.LiveView.ColocatedHook`'s merged manifest
  # (`_build/#{Mix.env()}/phoenix-colocated/flicker/index.js` and its
  # per-hook fragment files, see `mix.exs`'s `compilers:` comment) so
  # `dev/layouts.ex`'s import-mapped `<script type="module">` can load
  # `.Nav`/`.Palette`/`.FlickerSearchNav` — no asset pipeline, so this
  # stands in for what a host app's bundler would otherwise resolve.
  plug(Plug.Static,
    at: "/phoenix-colocated/flicker",
    from: Path.join([Mix.Project.build_path(), "phoenix-colocated", "flicker"])
  )

  plug(Plug.Session, @session_options)
  plug(Dev.Router)
end
