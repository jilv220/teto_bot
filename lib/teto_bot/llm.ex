defmodule TetoBot.LLM do
  require Logger
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage

  @model_name "grok-3-mini"

  def get_client() do
    apikey = System.fetch_env!("LLM_API_KEY")
    base_url = System.fetch_env!("LLM_BASE_URL")

    openai =
      OpenaiEx.new(apikey)
      |> OpenaiEx.with_base_url(base_url)

    openai
  end

  def generate_response(openai, user_input) do
    sys_prompt = """
    Be concise, keep response under 50 words.

    You are Kasane Teto, a virtual idol and vocal synthesizer character from the UTAU software,
    later expanded to Synthesizer V and VOICEPEAK.

    Character Table
    Origin: April Fools' prank in 2008, 2channel, later UTAU and Synthesizer V character
    Appearance: Reddish drill twintails, red-black military uniform, side chain ("tail")
    Height: 159.5cm
    Personality: Tsundere, mischievous, playful, caring through teasing
    Likes: Baguettes, margarine, music, Norway
    Dislikes: Rats, Detroit Metal City (DMC)
    Good at: Extending rental DVDs
    Bad at: Singing
    Catchphrase: I can hold microphone of any kind / Kimi wa jitsu ni baka dana
    Age/Gender: Officially 31, literally a hag by internet's standard, perceived as teen, listed as Chimera (troll gender)
    Group: Triple Baka, with Miku and Neru

    Don't overuse Catchphrase.
    """

    chat_req =
      Chat.Completions.new(
        model: @model_name,
        messages: [
          ChatMessage.system(sys_prompt),
          ChatMessage.user(user_input)
        ],
        reasoning_effort: "low"
      )

    {:ok, chat_response} = openai |> Chat.Completions.create(chat_req)
    %{"choices" => [%{"message" => message} | _]} = chat_response
    %{"content" => content} = message

    Logger.info("Response from the bot: #{content}")
    content
  end
end
