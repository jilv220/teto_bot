defmodule TetoBot.Accounts.User.Role do
  use Ash.Type.Enum, values: [:user, :admin]
end
