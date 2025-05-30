defmodule TetoBot.Mox do
  Mox.defmock(TetoBot.Channels.CacheMock, for: TetoBot.Channels.CacheBehaviour)
  Mox.defmock(TetoBot.RepoMock, for: Ecto.Repo)
end
