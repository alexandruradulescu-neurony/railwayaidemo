defmodule Showcase.OrderFlow.ClientResolver do
  @moduledoc """
  Maps a `client_hint` (free-text name extracted from the message) to a
  Client row. Returns `{:ok, client}` if any of these resolution strategies
  succeed, else `{:needs_human, reason}`:

    1. **Exact** case-insensitive name match.
    2. **Substring** — client name is a substring of the hint
       (handles "Meesenburg Romania SRL" → "Meesenburg Romania")
       — or vice versa (handles "Meesenburg" → "Meesenburg Romania").
    3. **Email** — hint contains an `@`; we match against the client's
       email (or domain portion) substring.
  """

  import Ecto.Query

  alias Showcase.OrderFlow.Schemas.Client

  @spec resolve(String.t() | nil, Ecto.Repo.t()) ::
          {:ok, Client.t()} | {:needs_human, String.t()}
  def resolve(nil, _repo), do: {:needs_human, "no client hint in message"}

  def resolve(hint, repo) when is_binary(hint) do
    normalized = String.downcase(String.trim(hint))

    with :no_match <- try_exact(normalized, repo),
         :no_match <- try_substring(normalized, repo),
         :no_match <- try_email(normalized, repo) do
      {:needs_human, "no matching client for hint: #{inspect(hint)}"}
    else
      {:match, client} -> {:ok, client}
    end
  end

  defp try_exact(normalized, repo) do
    case repo.one(from c in Client, where: fragment("lower(?)", c.name) == ^normalized) do
      nil -> :no_match
      %Client{} = c -> {:match, c}
    end
  end

  defp try_substring(normalized, repo) do
    # 1. client name appears inside the hint
    # 2. hint appears inside the client name
    # Match shortest result so "Meesenburg" prefers a "Meesenburg Romania"
    # over a hypothetical "Meesenburg Romania SRL".
    query =
      from c in Client,
        where:
          fragment("position(lower(?) in ?) > 0", c.name, ^normalized) or
            fragment("position(? in lower(?)) > 0", ^normalized, c.name),
        order_by: fragment("char_length(?)", c.name),
        limit: 1

    case repo.one(query) do
      nil -> :no_match
      %Client{} = c -> {:match, c}
    end
  end

  defp try_email(normalized, repo) do
    cond do
      String.contains?(normalized, "@") ->
        # The hint looks like an address — match either the full email or the
        # domain part against any client.email.
        query =
          from c in Client,
            where: not is_nil(c.email),
            where:
              fragment("position(lower(?) in ?) > 0", c.email, ^normalized) or
                fragment("position(? in lower(?)) > 0", ^normalized, c.email),
            limit: 1

        case repo.one(query) do
          nil -> :no_match
          %Client{} = c -> {:match, c}
        end

      true ->
        :no_match
    end
  end
end
