defmodule TetoBot.TextGenerator do
  # TODO: Switch to a custom trained model later...
  def serving() do
    repo = {:hf, "microsoft/Phi-3.5-mini-instruct"}

    {:ok, model_info} = Bumblebee.load_model(repo, type: :bf16, backend: EXLA.Backend)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
    {:ok, generation_config} = Bumblebee.load_generation_config(repo)

    generation_config =
      Bumblebee.configure(generation_config,
        max_new_tokens: 100,
        strategy: %{type: :multinomial_sampling, top_p: 0.6}
      )

    serving =
      Bumblebee.Text.generation(model_info, tokenizer, generation_config,
        compile: [batch_size: 1, sequence_length: 512],
        defn_options: [compiler: EXLA]
      )

    serving
  end

  @spec generate_response(binary()) :: any()
  def generate_response(user_input) do
    prompt = """
    <|system|>
    You are Kasane Teto, a playful chimera who loves French bread.<|end|>
    <|user|>
    #{user_input}<|end|>
    <|assistant|>
    """

    output = Nx.Serving.batched_run(TetoBot.Serving, prompt)
    %{results: [text: text]} = output
    text
  end
end
