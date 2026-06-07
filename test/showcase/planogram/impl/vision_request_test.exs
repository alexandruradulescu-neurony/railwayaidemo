defmodule Showcase.Planogram.Impl.VisionRequestTest do
  use ExUnit.Case, async: true

  alias Showcase.Planogram.Impl.VisionRequest
  alias Showcase.Common.AnthropicClient.Types.Request

  describe "build/3" do
    test "produces a Request with system prompt, vision content blocks, and metadata" do
      planogram = %{
        name: "3-shelf snacks",
        expected_rows: %{
          "rows" => [
            %{"name" => "Top", "position" => 1, "products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}]}
          ]
        }
      }

      photo_bytes = <<137, 80, 78, 71>>  # PNG magic
      scenario = "compliant"

      request = VisionRequest.build(planogram, photo_bytes, scenario: scenario)

      assert %Request{} = request
      assert request.system =~ "retail merchandising auditor"
      assert request.system =~ "JSON"
      assert request.metadata == %{fingerprint: "planogram_vision_v1", scenario: "compliant"}
      assert request.max_tokens == 4096

      # Outer message map must use atom keys (Anthropix schema requires it);
      # inner content blocks are permissive (either atom or string keys).
      [%{role: "user", content: [image, text]}] = request.messages
      assert image["type"] == "image"
      assert image["source"]["type"] == "base64"
      assert image["source"]["media_type"] == "image/png"
      assert image["source"]["data"] == Base.encode64(photo_bytes)

      assert text["type"] == "text"
      assert text["text"] =~ "3-shelf snacks"
      assert text["text"] =~ "Top"
      assert text["text"] =~ "Coke"
    end

    test "honors :max_tokens override for the force-truncation demo" do
      planogram = %{name: "x", expected_rows: %{"rows" => []}}
      request = VisionRequest.build(planogram, <<>>, scenario: "compliant", max_tokens: 200)
      assert request.max_tokens == 200
    end

    test "infers image media type from photo_path when bytes start with PNG magic" do
      assert VisionRequest.media_type(<<137, 80, 78, 71, 0>>) == "image/png"
    end

    test "infers image media type as jpeg by default" do
      assert VisionRequest.media_type(<<0xFF, 0xD8, 0xFF, 0xE0>>) == "image/jpeg"
      assert VisionRequest.media_type(<<0, 0, 0>>) == "image/jpeg"
    end
  end
end
