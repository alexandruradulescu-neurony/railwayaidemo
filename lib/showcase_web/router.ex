defmodule ShowcaseWeb.Router do
  use ShowcaseWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ShowcaseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin do
    plug ShowcaseWeb.Plugs.AdminBasicAuth
  end

  scope "/", ShowcaseWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/order-flow", OrderFlow.InboxLive
    live "/order-flow/orders/:id", OrderFlow.OrderDetailLive
    live "/invoice-approval", InvoiceApproval.QueueLive
    live "/invoice-approval/bundles/:id", InvoiceApproval.BundleDetailLive
  end

  scope "/admin", ShowcaseWeb do
    pipe_through [:browser, :admin]

    # Stub pages — replaced by real LiveViews in later phases
    live "/system-prompts", Admin.SystemPromptsLive
    live "/reset", Admin.ResetLive
    live "/audit-log", Admin.AuditLogLive
  end

  scope "/admin" do
    pipe_through [:browser, :admin]

    live_dashboard "/dashboard", metrics: ShowcaseWeb.Telemetry
  end

  # Other scopes may use custom stacks.
  # scope "/api", ShowcaseWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:showcase, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
