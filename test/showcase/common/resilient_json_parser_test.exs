defmodule Showcase.Common.ResilientJSONParserTest do
  use ExUnit.Case, async: true

  alias Showcase.Common.ResilientJSONParser, as: Parser

  describe "parse/1 with well-formed input" do
    test "decodes a plain object" do
      assert {:ok, %{"a" => 1}, :complete} = Parser.parse(~s({"a": 1}))
    end

    test "decodes a plain array" do
      assert {:ok, [1, 2, 3], :complete} = Parser.parse(~s([1, 2, 3]))
    end

    test "decodes nested structures" do
      input = ~s({"items": [{"name": "x"}, {"name": "y"}]})

      assert {:ok, %{"items" => [%{"name" => "x"}, %{"name" => "y"}]}, :complete} =
               Parser.parse(input)
    end
  end

  describe "parse/1 with truncation or salvageable malformed input" do
    test "salvages a truncated object (missing closing brace)" do
      assert {:ok, %{"a" => 1}, :partial} = Parser.parse(~s({"a": 1))
    end

    test "salvages a truncated array (missing closing bracket)" do
      assert {:ok, [1, 2], :partial} = Parser.parse(~s([1, 2))
    end

    test "salvages truncation mid-string" do
      assert {:ok, %{"a" => "hello"}, :partial} = Parser.parse(~s({"a": "hello))
    end

    test "salvages truncation mid-key" do
      # Truncated mid-key — the partial key/value gets dropped, prior keys preserved
      assert {:ok, %{"a" => 1}, :partial} = Parser.parse(~s({"a": 1, "bro))
    end

    test "salvages deeply nested truncation" do
      input = ~s({"items": [{"name": "x"}, {"name": "y)
      assert {:ok, %{"items" => [%{"name" => "x"}]}, :partial} = Parser.parse(input)
    end

    test "salvages truncation after comma" do
      assert {:ok, %{"a" => 1}, :partial} = Parser.parse(~s({"a": 1,))
    end

    test "silently salvages structurally-invalid trailing garbage" do
      # When the parser encounters tokens that don't fit the JSON grammar
      # *after* a valid value, it salvages the prefix and returns :partial.
      # This is deliberate — LLMs sometimes babble after a valid response —
      # but callers should not assume :partial means "truncated mid-stream".
      assert {:ok, %{"a" => "b"}, :partial} = Parser.parse(~s({"a": "b": "c"}))
    end
  end

  describe "parse/1 with unrecoverable input" do
    test "returns error for empty input" do
      assert {:error, _reason} = Parser.parse("")
    end

    test "returns error for garbage" do
      assert {:error, _reason} = Parser.parse("not json at all")
    end

    test "returns error for malformed key" do
      # Key without quotes is invalid and unrecoverable
      assert {:error, _reason} = Parser.parse(~s({a: 1}))
    end
  end

  describe "property: well-formed JSON always round-trips" do
    use ExUnitProperties

    property "any decodable Jason input parses with :complete" do
      check all(data <- json_term()) do
        encoded = Jason.encode!(data)
        assert {:ok, decoded, :complete} = Parser.parse(encoded)
        assert decoded == data
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  defp json_term do
    StreamData.tree(
      StreamData.one_of([
        StreamData.integer(),
        StreamData.float(),
        StreamData.boolean(),
        StreamData.string(:printable),
        StreamData.constant(nil)
      ]),
      fn child ->
        StreamData.one_of([
          StreamData.list_of(child, max_length: 5),
          StreamData.map_of(
            StreamData.string(:alphanumeric, min_length: 1, max_length: 8),
            child,
            max_length: 5
          )
        ])
      end
    )
  end
end
