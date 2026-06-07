defmodule Showcase.Planogram.Impl.VisionRequestTest do
  use ExUnit.Case, async: true

  alias Showcase.Planogram.Impl.VisionRequest
  alias Showcase.Common.AnthropicClient.Types.Request

  @planogram %{
    name: "3-shelf snacks",
    expected_rows: %{
      "rows" => [
        %{"name" => "Top", "position" => 1, "products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}]}
      ]
    }
  }

  describe "build/3 — single-image mode (no reference)" do
    test "produces a Request with one image + one text block, atom-keyed outer message" do
      photo_bytes = <<137, 80, 78, 71>>
      request = VisionRequest.build(@planogram, photo_bytes, scenario: "compliant")

      assert %Request{} = request
      assert request.system =~ "retail merchandising auditor"
      assert request.system =~ "JSON"
      assert request.metadata == %{fingerprint: "planogram_vision_v1", scenario: "compliant"}
      assert request.max_tokens == 4096

      # Outer message map atom keys; inner blocks string keys
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
  end

  describe "build/3 — two-image mode (reference + shelf)" do
    test "produces a Request with TWO image blocks followed by a text block" do
      reference = <<137, 80, 78, 71, 0xAA>>
      shelf = <<137, 80, 78, 71, 0xBB>>

      request =
        VisionRequest.build(@planogram, shelf,
          reference_bytes: reference,
          scenario: "compliant"
        )

      [%{role: "user", content: [ref_block, shelf_block, text_block]}] = request.messages

      # Reference is FIRST (image 1)
      assert ref_block["type"] == "image"
      assert ref_block["source"]["data"] == Base.encode64(reference)

      # Shelf is SECOND (image 2)
      assert shelf_block["type"] == "image"
      assert shelf_block["source"]["data"] == Base.encode64(shelf)

      # Text block instructs visual comparison
      assert text_block["type"] == "text"
      assert text_block["text"] =~ "REFERENCE"
      assert text_block["text"] =~ "ACTUAL"
      assert text_block["text"] =~ "Compare them visually"
    end

    test "system prompt mentions the new categorical issue types + extracted_prices" do
      request = VisionRequest.build(@planogram, <<>>, [])

      assert request.system =~ "extracted_prices"
      assert request.system =~ "out_of_stock"
      assert request.system =~ "wrong_placement"
      assert request.system =~ "horizontal_position"
    end
  end

  describe "build/3 — common knobs" do
    test "honors :max_tokens override" do
      request = VisionRequest.build(@planogram, <<>>, max_tokens: 200)
      assert request.max_tokens == 200
    end
  end

  describe "media_type/1" do
    test "detects PNG magic" do
      assert VisionRequest.media_type(<<137, 80, 78, 71, 0>>) == "image/png"
    end

    test "detects JPEG magic" do
      assert VisionRequest.media_type(<<0xFF, 0xD8, 0xFF, 0xE0>>) == "image/jpeg"
    end

    test "detects GIF magic" do
      assert VisionRequest.media_type(<<"GIF87a", 0>>) == "image/gif"
      assert VisionRequest.media_type(<<"GIF89a", 0>>) == "image/gif"
    end

    test "detects WebP magic" do
      assert VisionRequest.media_type(<<"RIFF", 0, 0, 0, 0, "WEBP", 0>>) == "image/webp"
    end

    test "falls back to image/jpeg for unknown bytes" do
      assert VisionRequest.media_type(<<0, 0, 0>>) == "image/jpeg"
    end
  end
end
