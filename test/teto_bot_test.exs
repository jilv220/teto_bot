defmodule TetoBotTest do
  use ExUnit.Case
  doctest TetoBot

  test "greets the world" do
    assert TetoBot.hello() == :world
  end
end
