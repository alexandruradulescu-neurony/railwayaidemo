defmodule Showcase.Common.ResilientJSONParserTest do
  use ExUnit.Case, async: true

  alias Showcase.Common.ResilientJSONParser, as: Parser

  describe "parse/1 with well-formed input" do
    test "decodes a plain object" do
      assert {:ok, %{"a" => 1}, complete: true} = Parser.parse(~s({"a": 1}))
    end

    test "decodes a plain array" do
      assert {:ok, [1, 2, 3], complete: true} = Parser.parse(~s([1, 2, 3]))
    end

    test "decodes nested structures" do
      input = ~s({"items": [{"name": "x"}, {"name": "y"}]})

      assert {:ok, %{"items" => [%{"name" => "x"}, %{"name" => "y"}]}, complete: true} =
               Parser.parse(input)
    end
  end

  describe "parse/1 with truncation" do
    test "salvages a truncated object (missing closing brace)" do
      assert {:ok, %{"a" => 1}, complete: false} = Parser.parse(~s({"a": 1))
    end

    test "salvages a truncated array (missing closing bracket)" do
      assert {:ok, [1, 2], complete: false} = Parser.parse(~s([1, 2))
    end

    test "salvages truncation mid-string" do
      assert {:ok, %{"a" => "hello"}, complete: false} = Parser.parse(~s({"a": "hello))
    end

    test "salvages truncation mid-key" do
      # Truncated mid-key — the partial key/value gets dropped, prior keys preserved
      assert {:ok, %{"a" => 1}, complete: false} = Parser.parse(~s({"a": 1, "bro))
    end

    test "salvages deeply nested truncation" do
      input = ~s({"items": [{"name": "x"}, {"name": "y)
      assert {:ok, %{"items" => [%{"name" => "x"}]}, complete: false} = Parser.parse(input)
    end

    test "salvages truncation after comma" do
      assert {:ok, %{"a" => 1}, complete: false} = Parser.parse(~s({"a": 1,))
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

    property "any decodable Jason input parses with complete: true" do
      check all(
              data <-
                one_of([
                  map_of(string(:alphanumeric, min_length: 1), integer()),
                  list_of(integer()),
                  integer(),
                  string(:alphanumeric)
                ])
            ) do
        encoded = Jason.encode!(data)
        assert {:ok, decoded, complete: true} = Parser.parse(encoded)
        assert decoded == data
      end
    end
  end
end
