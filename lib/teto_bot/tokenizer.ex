defmodule TetoBot.Tokenizer do
  @moduledoc """
  A GenServer for handling tokenization, ensuring the tokenizer is loaded only once.
  """
  use GenServer
  require Logger

  @name __MODULE__

  @doc """
  Starts the tokenizer GenServer.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: @name)
  end

  @doc """
  Gets the number of tokens in a string.
  """
  @spec get_token_count(String.t()) :: integer()
  def get_token_count(content) do
    GenServer.call(@name, {:get_token_count, content})
  end

  @impl true
  def init(_) do
    Logger.info("Loading tokenizer model...")
    {:ok, tokenizer} = Tokenizers.Tokenizer.from_pretrained("bert-base-cased")
    Logger.info("Tokenizer model loaded.")
    {:ok, tokenizer}
  end

  @impl true
  def handle_call({:get_token_count, content}, _from, tokenizer) do
    {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, content)
    {:reply, Tokenizers.Encoding.n_tokens(encoding), tokenizer}
  end
end
