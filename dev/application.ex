defmodule Dev.Application do
  @moduledoc """
  The OTP application callback for the dev playground (Spec 005).

  Only ever started when the compiling env is `:dev` — `mix.exs` sets
  `mod: {Dev.Application, []}` for `:dev` alone, so a `:test` or `:prod`
  build never boots this supervision tree even though `dev/` is on its
  `elixirc_paths` for `:test` too (Spec 004's harness needs it compiled,
  not running).
  """

  use Application

  @impl true
  @doc "Starts `Dev.PubSub` and `Dev.Endpoint` under a one-for-one supervisor."
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Dev.PubSub},
      Dev.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Dev.Supervisor)
  end
end
