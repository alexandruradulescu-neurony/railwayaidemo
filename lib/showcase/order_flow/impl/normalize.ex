defmodule Showcase.OrderFlow.Impl.Normalize do
  @moduledoc """
  Pure text normalization for matching.

  Steps applied (in order):
    1. lowercase
    2. strip common punctuation (`!`, `,`, `.`, `;`, `:`, `(`, `)`, `?`)
    3. collapse runs of whitespace into a single space
    4. trim surrounding whitespace

  Preserves digits, hyphens (for SKU-like tokens), and other alphanumeric chars.
  """

  @punctuation_pattern ~r/[!,.;:()?]/u

  @spec normalize_text(String.t()) :: String.t()
  def normalize_text(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(@punctuation_pattern, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
