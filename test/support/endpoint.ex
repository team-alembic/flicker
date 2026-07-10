defmodule Flicker.Test.Endpoint do
  @moduledoc """
  The test-support endpoint — never actually started as an HTTP server;
  `Phoenix.ConnTest` dispatches through it in-process, which is all
  PhoenixTest needs.
  """

  use Phoenix.Endpoint, otp_app: :flicker

  @session_options [
    store: :cookie,
    key: "_flicker_test_key",
    signing_salt: "flicker-test-salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Session, @session_options)
  plug(:put_secret_key_base)
  plug(Flicker.Test.Router)

  defp put_secret_key_base(conn, _opts) do
    Plug.Conn.put_private(conn, :phoenix_endpoint, __MODULE__)
  end
end
