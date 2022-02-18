defmodule BorutaAuth.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      BorutaAuth.Repo
    ]

    opts = [strategy: :one_for_one, name: BorutaAuth.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
