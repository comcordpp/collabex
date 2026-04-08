defmodule CollabExWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :collabex_web

  socket "/collabex", CollabExWeb.RoomSocket,
    websocket: [timeout: 45_000],
    longpoll: false

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Jason

  plug CollabExWeb.Router
end
