defmodule TetoBot.Format do
  def format_time_left(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    seconds_left = rem(seconds, 60)

    case {hours, minutes, seconds_left} do
      {0, 0, s} -> "#{s} second#{if s != 1, do: "s", else: ""}"
      {0, m, s} -> "#{m}m #{s}sec"
      {h, m, _s} -> "#{h}h #{m}min"
    end
  end
end
