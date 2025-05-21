defmodule TetoBot.RateLimiter do
  def allow?(user_id) do
    window = Application.get_env(:teto_bot, :rate_limit_window, 60)
    max_requests = Application.get_env(:teto_bot, :rate_limit_max_requests, 5)
    now = System.monotonic_time(:second)

    case :ets.lookup(:rate_limit, user_id) do
      [{_, count, last_time}] ->
        if now - last_time > window do
          :ets.insert(:rate_limit, {user_id, 1, now})
          true
        else
          if count < max_requests do
            :ets.insert(:rate_limit, {user_id, count + 1, last_time})
            true
          else
            false
          end
        end

      [] ->
        :ets.insert(:rate_limit, {user_id, 1, System.monotonic_time(:second)})
        true
    end
  end
end
