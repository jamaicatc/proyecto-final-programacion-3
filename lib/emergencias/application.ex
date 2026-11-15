defmodule Emergencias.Application do
  # Arbol de supervision OTP del sistema.
  @moduledoc "Supervisión de procesos del sistema de emergencias en consola."
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Emergencias.TaskSupervisor},
      {Emergencias.Coordinator, name: Emergencias.Coordinator}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: Emergencias.Supervisor) do
      {:ok, sup} ->
        # Los procesos supervisados deben conservar acceso a la terminal.
        # Su group leader por defecto es el application master, que no acepta
        # entrada estándar; se propaga el group leader del usuario cuando existe.
        if user = Process.whereis(:user) do
          sup
          |> Supervisor.which_children()
          |> Enum.each(fn {_id, pid, _type, _modules} ->
            if is_pid(pid), do: Process.group_leader(pid, user)
          end)
        end

        if Application.get_env(:emergencias, :start_cli, false) do
          Task.Supervisor.start_child(Emergencias.TaskSupervisor, fn ->
            Emergencias.Terminal.start()
          end)
        end

        {:ok, sup}

      other ->
        other
    end
  end
end
