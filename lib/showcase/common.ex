defmodule Showcase.Common do
  @moduledoc """
  Shared infrastructure domain. Holds resources used by every demo:
  - `SystemPrompt` — live-editable LLM prompts, scoped by demo + section
  - `AuditLog`    — append-only event store
  """

  use Ash.Domain, otp_app: :showcase

  resources do
    resource Showcase.Common.SystemPrompt
    resource Showcase.Common.AuditLog
  end
end
