defmodule CollabEx.Repo do
  use Ecto.Repo,
    otp_app: :collabex,
    adapter: Ecto.Adapters.Postgres
end
