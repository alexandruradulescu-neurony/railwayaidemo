defmodule Showcase.OrderFlow.ClientResolver do
  @moduledoc """
  Maps a `client_hint` (free-text name extracted from the message) to a
  Client row. Returns `{:ok, client}` on case-insensitive name match,
  `{:needs_human, reason}` otherwise.
  """

  import Ecto.Query

  alias Showcase.OrderFlow.Schemas.Client

  @spec resolve(String.t() | nil, Ecto.Repo.t()) ::
          {:ok, Client.t()} | {:needs_human, String.t()}
  def resolve(nil, _repo), do: {:needs_human, "no client hint in message"}

  def resolve(hint, repo) when is_binary(hint) do
    normalized = String.downcase(String.trim(hint))

    case repo.one(from c in Client, where: fragment("lower(?)", c.name) == ^normalized) do
      nil -> {:needs_human, "no matching client for hint: #{inspect(hint)}"}
      %Client{} = client -> {:ok, client}
    end
  end
end
