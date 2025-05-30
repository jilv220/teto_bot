defmodule TetoBot.Factory do
  use ExMachina.Ecto, repo: TetoBot.Repo

  def channel_factory do
    %TetoBot.Channels.Channel{
      channel_id: 123_456_789
    }
  end
end
