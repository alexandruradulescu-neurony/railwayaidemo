defmodule Showcase.Common.AnthropicClientTest do
  use ExUnit.Case, async: true

  test "dispatcher routes to configured impl (Mock in test env)" do
    impl = Application.get_env(:showcase, :anthropic_client_impl)
    assert impl == Showcase.Common.AnthropicClient.Mock
  end
end
