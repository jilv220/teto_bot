defmodule TetoBot.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias TetoBot.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import TetoBot.DataCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TetoBot.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(TetoBot.Repo, {:shared, self()})
    end

    :ok
  end
end
