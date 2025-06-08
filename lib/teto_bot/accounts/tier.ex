defmodule TetoBot.Accounts.Tier do
  @moduledoc """
  Manages intimacy tiers, providing functions to retrieve tier information
  based on intimacy scores.

  This module encapsulates the logic for defining intimacy tiers and calculating
  a user's current and next tier progression.
  """

  @intimacy_tiers [
    {1000, "Husband"},
    {500, "Best Friend"},
    {200, "Close Friend"},
    {101, "Good Friend"},
    {51, "Friend"},
    {21, "Buddy"},
    {11, "Acquaintance"},
    {5, "Familiar Face"},
    {0, "Stranger"}
  ]
  @tier_values Map.new(@intimacy_tiers, fn {value, name} -> {name, value} end)

  @doc """
  Returns the intimacy tier name for a given intimacy score.
  """
  @spec get_tier_name(integer()) :: String.t()
  def get_tier_name(intimacy) do
    {_, intimacy_tier} =
      @intimacy_tiers
      |> Enum.find(fn {k, _v} -> intimacy >= k end)

    intimacy_tier
  end

  @doc """
  Returns current tier information and next tier information for a given intimacy score.
  """
  @spec get_tier_info(integer()) :: {{integer(), binary()}, {integer(), binary()}}
  def get_tier_info(intimacy) do
    curr_intimacy_idx =
      @intimacy_tiers
      |> Enum.find_index(fn {k, _v} -> intimacy >= k end)

    {_, curr_intimacy_tier} =
      @intimacy_tiers
      |> Enum.at(curr_intimacy_idx)

    next_tier_intimacy_entry =
      if curr_intimacy_idx == 0 do
        # Already at highest tier, return same tier
        {intimacy, curr_intimacy_tier}
      else
        @intimacy_tiers |> Enum.at(curr_intimacy_idx - 1)
      end

    {{intimacy, curr_intimacy_tier}, next_tier_intimacy_entry}
  end

  @doc """
  Retrieves the intimacy value for a given tier name.
  """
  @spec get_tier_value(String.t()) :: {:ok, integer()} | {:error, :invalid_tier}
  def get_tier_value(tier_name) when is_binary(tier_name) do
    case Map.get(@tier_values, tier_name) do
      nil -> {:error, :invalid_tier}
      value -> {:ok, value}
    end
  end

  def get_tier_value(tier_name) do
    tier_name
    |> normalize_tier_atom()
    |> get_tier_value()
  end

  defp normalize_tier_atom(tier_atom) when is_atom(tier_atom) do
    tier_atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
