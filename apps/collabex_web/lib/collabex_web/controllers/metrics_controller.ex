defmodule CollabExWeb.MetricsController do
  @moduledoc """
  Serves Prometheus metrics at /metrics for scraping.
  """
  use Phoenix.Controller, formats: [:text]

  def index(conn, _params) do
    metrics = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end
end
