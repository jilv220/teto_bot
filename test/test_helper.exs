# Configure StreamData for property-based testing
Application.put_env(:stream_data, :max_runs, 10)

ExUnit.start()

# Set up Ecto Sandbox for database transactions
Ecto.Adapters.SQL.Sandbox.mode(TetoBot.Repo, :manual)
