defmodule Showcase.Common.Config do
  @moduledoc """
  Centralized accessors for runtime config the demos read.
  """

  @spec default_model() :: String.t()
  def default_model do
    Application.get_env(:showcase, :anthropic_default_model, "claude-haiku-4-5-20251001")
  end
end
