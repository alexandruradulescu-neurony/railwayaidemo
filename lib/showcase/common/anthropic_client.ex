defmodule Showcase.Common.AnthropicClient do
  @moduledoc """
  Behaviour for Anthropic API calls. Real and mock impls both conform.

  Use `Showcase.Common.AnthropicClient.call/2` everywhere in app code — never
  call the impl modules directly. The active impl is read from app config,
  letting tests swap in `Mock`.
  """

  alias Showcase.Common.AnthropicClient.Types.{Request, Response}

  @doc """
  Issue a single (non-streaming) Anthropic call.

  Returns `{:ok, %Response{}}` or `{:error, term()}`.
  """
  @callback call(Request.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}

  @spec call(Request.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def call(%Request{} = req, opts \\ []) do
    impl().call(req, opts)
  end

  defp impl do
    Application.get_env(:showcase, :anthropic_client_impl, Showcase.Common.AnthropicClient.Live)
  end
end
