defmodule Showcase.Common.ResilientJSONParser do
  @moduledoc """
  Parses JSON that may be truncated, salvaging what it can.

  When `Jason.decode/1` succeeds on the input, returns the decoded term with
  `complete: true`. When it fails (e.g. an LLM response was cut off mid-stream),
  the parser walks the input collecting positions where the prefix-so-far is a
  parsable JSON document once balanced with synthesized closing brackets. It
  then walks those candidates back-to-front, retrying the parse until one
  succeeds.

  Returns:
    * `{:ok, term, complete: true}` — input parsed cleanly
    * `{:ok, term, complete: false}` — input was truncated, partial parse salvaged
    * `{:error, reason}` — input was unrecoverable
  """

  @spec parse(binary()) ::
          {:ok, term(), [{:complete, boolean()}]} | {:error, term()}
  def parse(input) when is_binary(input) do
    case Jason.decode(input) do
      {:ok, value} ->
        {:ok, value, complete: true}

      {:error, _reason} ->
        salvage(input)
    end
  end

  # ---------------------------------------------------------------------------
  # Salvage path
  # ---------------------------------------------------------------------------

  defp salvage("") do
    {:error, :empty_input}
  end

  defp salvage(input) do
    # Collect candidate truncation points by walking the input once. Each
    # candidate is a tuple {prefix_length, stack, suffix} where `stack` is
    # the list of currently-open containers and `suffix` is any extra
    # string to splice in before the synthesized closers (e.g. `"` if the
    # input was truncated mid-string).
    #
    # `real_candidates` are positions where a complete value boundary was
    # observed. `fallback_candidates` are best-effort guesses (e.g. closing
    # a partial string) that are only tried after all real ones fail.
    {real_candidates, fallback_candidates} = collect_candidates(input)

    case try_candidates(input, real_candidates) do
      {:ok, value} ->
        {:ok, value, complete: false}

      :error ->
        case try_candidates(input, fallback_candidates) do
          {:ok, value} -> {:ok, value, complete: false}
          :error -> {:error, :unrecoverable}
        end
    end
  end

  # Walk the input and record, after each "complete value" boundary, the
  # position and the open-container stack. Also detect whether the input
  # ended inside a string so we can synthesize a closing quote.
  defp collect_candidates(input) do
    {acc, eof_state} = do_walk(input, 0, [], false, false, [])

    real = Enum.reverse(acc)

    # If the input ended inside a string used as a value (object value or
    # array element), build a fallback candidate that closes the string
    # with `"`. We can't recover a truncated *key* because we don't have
    # an associated value to attach to it.
    fallback =
      case eof_state do
        {:in_string, _pos, [:object_expecting_value | parent_stack]} ->
          [{byte_size(input), [:object_after_value | parent_stack], "\""}]

        {:in_string, _pos, [:array_expecting_value | parent_stack]} ->
          [{byte_size(input), [:array_after_value | parent_stack], "\""}]

        _ ->
          []
      end

    {real, fallback}
  end

  # Walker state machine.
  #
  # Args:
  #   rest: remaining input
  #   pos: byte index of next char (i.e. length of prefix already consumed)
  #   stack: list of open containers, head = innermost. Each entry is one of:
  #          :object_expecting_key, :object_expecting_value, :object_after_value,
  #          :array_expecting_value, :array_after_value
  #   in_string?: are we currently inside a JSON string literal
  #   escape?: was the previous char in a string a backslash
  #   acc: accumulated candidate list (newest first)
  #
  # Returns {acc, eof_state} where eof_state is one of:
  #   :clean — walker hit EOF outside a string at a stable position
  #   :unexpected — walker hit something it didn't understand
  #   {:in_string, str_start_pos, stack_at_open} — EOF inside a string literal
  defp do_walk(<<>>, _pos, _stack, false, false, acc), do: {acc, :clean}

  defp do_walk(<<>>, pos, stack, true, _escape?, acc) do
    # We ended inside a string. We don't track the string's start position
    # through the walker, so pass `pos` and the stack that was active when
    # the string opened — but `stack` here is the stack AT eof, which is
    # the stack DURING the string. For our purposes we only care about the
    # innermost open container's role (key vs value), which the stack already
    # tells us.
    {acc, {:in_string, pos, stack}}
  end

  # --- inside a string ---
  defp do_walk(<<?\\, rest::binary>>, pos, stack, true, false, acc) do
    do_walk(rest, pos + 1, stack, true, true, acc)
  end

  defp do_walk(<<_c, rest::binary>>, pos, stack, true, true, acc) do
    # Consume the escaped character without state change
    do_walk(rest, pos + 1, stack, true, false, acc)
  end

  defp do_walk(<<?", rest::binary>>, pos, stack, true, false, acc) do
    # Closing quote of a string. Handle in stack context.
    new_stack = on_string_close(stack)
    new_pos = pos + 1

    acc =
      if value_closed?(new_stack) do
        [{new_pos, new_stack, ""} | acc]
      else
        acc
      end

    do_walk(rest, new_pos, new_stack, false, false, acc)
  end

  defp do_walk(<<_c, rest::binary>>, pos, stack, true, false, acc) do
    # Any other char inside string
    do_walk(rest, pos + 1, stack, true, false, acc)
  end

  # --- outside a string ---
  defp do_walk(<<c, rest::binary>>, pos, stack, false, false, acc)
       when c in [?\s, ?\t, ?\n, ?\r] do
    do_walk(rest, pos + 1, stack, false, false, acc)
  end

  defp do_walk(<<?", rest::binary>>, pos, stack, false, false, acc) do
    # Opening a string. No candidate yet; wait for close.
    do_walk(rest, pos + 1, stack, true, false, acc)
  end

  defp do_walk(<<?{, rest::binary>>, pos, stack, false, false, acc) do
    do_walk(rest, pos + 1, [:object_expecting_key | stack], false, false, acc)
  end

  defp do_walk(<<?[, rest::binary>>, pos, stack, false, false, acc) do
    do_walk(rest, pos + 1, [:array_expecting_value | stack], false, false, acc)
  end

  defp do_walk(<<?}, rest::binary>>, pos, stack, false, false, acc) do
    # Closing object: pop then promote parent to "after_value"
    new_stack = pop_and_promote(stack)
    new_pos = pos + 1

    acc =
      if value_closed?(new_stack) do
        [{new_pos, new_stack, ""} | acc]
      else
        acc
      end

    do_walk(rest, new_pos, new_stack, false, false, acc)
  end

  defp do_walk(<<?], rest::binary>>, pos, stack, false, false, acc) do
    new_stack = pop_and_promote(stack)
    new_pos = pos + 1

    acc =
      if value_closed?(new_stack) do
        [{new_pos, new_stack, ""} | acc]
      else
        acc
      end

    do_walk(rest, new_pos, new_stack, false, false, acc)
  end

  defp do_walk(
         <<?:, rest::binary>>,
         pos,
         [:object_expecting_value | _] = stack,
         false,
         false,
         acc
       ) do
    # The colon separates key and value. We've moved from "have key" to
    # "expecting value". Stack already reflects this via on_string_close.
    do_walk(rest, pos + 1, stack, false, false, acc)
  end

  defp do_walk(<<?,, rest::binary>>, pos, stack, false, false, acc) do
    # Comma: transition based on what container we're in
    new_stack =
      case stack do
        [:object_after_value | t] -> [:object_expecting_key | t]
        [:array_after_value | t] -> [:array_expecting_value | t]
        other -> other
      end

    # A comma at the top of a container is a safe boundary — the prefix
    # (without the comma) is parsable. Record the position *before* the comma.
    acc =
      if can_truncate_before_comma?(stack) do
        [{pos, stack, ""} | acc]
      else
        acc
      end

    do_walk(rest, pos + 1, new_stack, false, false, acc)
  end

  # --- bare values (numbers, true, false, null) ---
  defp do_walk(<<c, _::binary>> = bin, pos, stack, false, false, acc)
       when c in ?0..?9 or c == ?- or c == ?t or c == ?f or c == ?n do
    case consume_bare_value(bin, pos) do
      {:ok, new_rest, new_pos} ->
        new_stack = promote_after_value(stack)

        acc =
          if value_closed?(new_stack) do
            [{new_pos, new_stack, ""} | acc]
          else
            acc
          end

        do_walk(new_rest, new_pos, new_stack, false, false, acc)

      :error ->
        # Unrecognized bare value — bail out, no more candidates from here.
        {acc, :unexpected}
    end
  end

  # Anything else outside a string is unexpected — stop collecting candidates.
  defp do_walk(_rest, _pos, _stack, false, false, acc), do: {acc, :unexpected}

  # ---------------------------------------------------------------------------
  # Stack transitions
  # ---------------------------------------------------------------------------

  # When a string literal closes, advance the innermost container's state.
  defp on_string_close([:object_expecting_key | t]), do: [:object_expecting_value | t]
  defp on_string_close([:object_expecting_value | t]), do: [:object_after_value | t]
  defp on_string_close([:array_expecting_value | t]), do: [:array_after_value | t]
  # String at top level (no container) — stack stays empty.
  defp on_string_close([]), do: []
  defp on_string_close(other), do: other

  # When a {} or [] closes (pop), the parent container moves to "after_value".
  defp pop_and_promote([_innermost | t]), do: promote_after_value(t)
  defp pop_and_promote([]), do: []

  defp promote_after_value([:object_expecting_value | t]), do: [:object_after_value | t]
  defp promote_after_value([:array_expecting_value | t]), do: [:array_after_value | t]
  defp promote_after_value(other), do: other

  # A value just closed at this point — is the resulting state a safe truncation
  # point? Yes if the value is at the top of a container that is now "after_value"
  # (we can close all open containers), OR if the stack is empty (full value).
  defp value_closed?([]), do: true
  defp value_closed?([:object_after_value | _]), do: true
  defp value_closed?([:array_after_value | _]), do: true
  defp value_closed?(_), do: false

  defp can_truncate_before_comma?([:object_after_value | _]), do: true
  defp can_truncate_before_comma?([:array_after_value | _]), do: true
  defp can_truncate_before_comma?(_), do: false

  # ---------------------------------------------------------------------------
  # Bare value scanning (number, true, false, null)
  # ---------------------------------------------------------------------------

  defp consume_bare_value(<<"true", rest::binary>>, pos), do: {:ok, rest, pos + 4}
  defp consume_bare_value(<<"false", rest::binary>>, pos), do: {:ok, rest, pos + 5}
  defp consume_bare_value(<<"null", rest::binary>>, pos), do: {:ok, rest, pos + 4}

  defp consume_bare_value(bin, pos) do
    case consume_number(bin, 0) do
      0 -> :error
      len -> {:ok, binary_part(bin, len, byte_size(bin) - len), pos + len}
    end
  end

  defp consume_number(<<c, rest::binary>>, len)
       when c in ?0..?9 or c in [?-, ?+, ?., ?e, ?E] do
    consume_number(rest, len + 1)
  end

  defp consume_number(_rest, len), do: len

  # ---------------------------------------------------------------------------
  # Try candidates back-to-front
  # ---------------------------------------------------------------------------

  defp try_candidates(_input, []), do: :error

  defp try_candidates(input, candidates) do
    # Walk from longest prefix to shortest. `candidates` is in ascending
    # position order; reverse to descend.
    candidates
    |> Enum.reverse()
    |> Enum.find_value(:error, fn {prefix_len, stack, suffix} ->
      candidate = build_candidate(input, prefix_len, stack, suffix)

      case Jason.decode(candidate) do
        {:ok, value} -> {:ok, value}
        {:error, _} -> nil
      end
    end)
  end

  defp build_candidate(input, prefix_len, stack, suffix) do
    prefix = binary_part(input, 0, prefix_len)
    closers = closers_for(stack)
    prefix <> suffix <> closers
  end

  defp closers_for(stack) do
    stack
    |> Enum.map(&closer_for/1)
    |> Enum.join()
  end

  defp closer_for(:object_expecting_key), do: "}"
  defp closer_for(:object_expecting_value), do: "}"
  defp closer_for(:object_after_value), do: "}"
  defp closer_for(:array_expecting_value), do: "]"
  defp closer_for(:array_after_value), do: "]"
end
