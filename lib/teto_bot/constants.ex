defmodule TetoBot.Constants do
  @moduledoc """
  Defines constants for the TetoBot application.
  """
  import Bitwise

  @interaction_response_type 4

  @ephemeral_flag 1 <<< 6

  def interaction_response_type, do: @interaction_response_type
  def ephemeral_flag, do: @ephemeral_flag
end
