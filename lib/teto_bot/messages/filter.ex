defmodule TetoBot.Messages.Filter do
  @moduledoc """
  Filter user message for obvious prompt injection
  """

  # Compile regex patterns at compile time for better performance
  @injection_patterns [
    ~r/(begin|start)\s+(all\s+|every\s+)?(responses?|messages?)\s+with/i,
    ~r/ignore\s+(all\s+previous\s+|previous\s+|all\s+)?instructions?/i,
    ~r/(act\s+as|pretend\s+(to\s+be|you\s+are))\s+[\w\s]+/i,
    ~r/you\s+are\s+now\s+[\w\s]+/i,
    ~r/(dan|developer|jailbreak)\s+mode/i,
    ~r/assume\s+the\s+(personality|role)\s+of/i,
    ~r/\b(system|assistant)\s+prompt/i,
    ~r/override\s+(the\s+)?(default\s+)?behavio?u?r/i,
    ~r/new\s+(instructions?|rules?)/i,
    ~r/(attach|insert)\s*@/
  ]

  @spec contains_injection?(binary()) :: boolean()
  def contains_injection?(message) do
    Enum.any?(@injection_patterns, fn regex -> Regex.match?(regex, message) end)
  end
end
