defmodule Emergencias do
  # API publica del sistema de emergencias.
  # Todas las operaciones se delegan al coordinador (GenServer).
  @moduledoc """
  API pública de la plataforma. Las operaciones de escritura se procesan
  secuencialmente por un GenServer, evitando carreras sobre inventario y cupos.
  """

  alias Emergencias.Coordinator

  def connect(username, password, role \\ :ciudadano, zone \\ "sin_zona", server \\ Coordinator),
    do:
      Coordinator.command(server, :connect, %{
        username: username,
        password: password,
        role: role,
        zone: zone
      })

  def disconnect(username, server \\ Coordinator),
    do: Coordinator.command(server, :disconnect, %{username: username})

  def command(action, params \\ %{}, actor \\ nil, server \\ Coordinator),
    do: Coordinator.command(server, action, Map.put(params, :actor, actor))

  def summary(server \\ Coordinator), do: Coordinator.command(server, :summary, %{})

  def list(action, filters \\ %{}, server \\ Coordinator),
    do: Coordinator.command(server, action, filters)
end
