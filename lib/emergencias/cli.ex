defmodule Emergencias.CLI do
  @moduledoc "Interfaz interactiva de comandos para la plataforma de emergencias."

  alias Emergencias.Coordinator

  @help """
  Comandos principales:
    connect USUARIO CLAVE [ciudadano|voluntario|coordinador|administrador] [ZONA]
    disconnect
    register_zone CODIGO NOMBRE NIVEL [AFECTADOS]
    register_sector ZONA CODIGO NOMBRE NIVEL [AFECTADOS]
    register_point ZONA SECTOR CODIGO NOMBRE [AFECTADOS]
    register_need TIPO CANTIDAD PRIORIDAD ZONA DESCRIPCION
    register_resource CODIGO NOMBRE CATEGORIA CANTIDAD UNIDAD ZONA
    assign_resource NECESIDAD RECURSO CANTIDAD
    transfer_resource RECURSO DESTINO CANTIDAD
    list_needs | list_resources | summary | pending_needs | critical_resources
    report_person DOCUMENTO NOMBRE ZONA ESTADO
    find_person DOCUMENTO_O_NOMBRE
    send_family_message DOCUMENTO "MENSAJE"
    list_family_messages DOCUMENTO
    report_pet lost|found ESPECIE NOMBRE COLOR TAMANO ZONA CONTACTO
    match_pets
    confirm_pet_match REPORTE_PERDIDO REPORTE_ENCONTRADO
    register_shelter CODIGO NOMBRE ZONA CAPACIDAD
    check_shelter CODIGO
    register_entry ALBERGUE DOCUMENTO | register_exit ALBERGUE DOCUMENTO
    help | quit

  Los textos con espacios deben ir entre comillas. La aplicación también se puede
  usar desde código mediante Emergencias.command/4.
  """

  def start(opts \\ []) do
    server = Keyword.get(opts, :server, Coordinator)

    Util2.mostrar(
      "Sistema de Coordinación de Emergencias. Escriba help para ver los comandos.",
      :mensaje
    )

    loop(nil, server)
  end

  defp loop(actor, server) do
    case IO.gets("#{if actor, do: actor, else: "desconectado"}> ") do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line when is_binary(line) ->
        tokens = tokenize(String.trim(line))

        case dispatch(tokens, actor, server) do
          :quit ->
            :ok

          {:result, result} ->
            display(result)
            loop(actor, server)

          {:result, result, next_actor} ->
            display(result)
            loop(next_actor, server)

          :continue ->
            loop(actor, server)
        end
    end
  end

  defp dispatch([], _actor, _server), do: :continue

  defp dispatch([command | args], actor, server) do
    case String.downcase(command) do
      "quit" ->
        :quit

      "exit" ->
        :quit

      "help" ->
        Util2.mostrar(@help, :mensaje)
        :continue

      "connect" ->
        connect(args, server)

      "disconnect" ->
        result =
          if actor,
            do: Emergencias.disconnect(actor, server),
            else: {:error, :usuario_no_conectado}

        {:result, result, nil}

      "register_zone" ->
        apply_command(:register_zone, args, actor, server)

      "register_sector" ->
        apply_command(:register_sector, args, actor, server)

      "register_point" ->
        apply_command(:register_point, args, actor, server)

      "register_need" ->
        apply_command(:register_need, args, actor, server)

      "register_resource" ->
        apply_command(:register_resource, args, actor, server)

      "adjust_resource" ->
        apply_command(:adjust_resource, args, actor, server)

      "assign_resource" ->
        apply_command(:assign_resource, args, actor, server)

      "transfer_resource" ->
        apply_command(:transfer_resource, args, actor, server)

      "list_needs" ->
        list(:list_needs, args, server)

      "pending_needs" ->
        {:result, Emergencias.list(:pending_needs, %{}, server)}

      "list_resources" ->
        list(:list_resources, args, server)

      "critical_resources" ->
        {:result, Emergencias.list(:critical_resources, %{}, server)}

      "report_person" ->
        apply_command(:report_person, args, actor, server)

      "update_person_status" ->
        apply_command(:update_person_status, args, actor, server)

      "find_person" ->
        do_find_person(args, server)

      "send_family_message" ->
        apply_command(:send_message, args, actor, server)

      "list_family_messages" ->
        list(:list_messages, args, server)

      "deliver_message" ->
        apply_command(:deliver_message, args, actor, server)

      "report_pet" ->
        apply_command(:report_pet, args, actor, server)

      "list_pets" ->
        list(:list_pets, args, server)

      "list_people" ->
        list(:list_people, args, server)

      "list_movements" ->
        {:result, Emergencias.list(:list_movements, %{}, server)}

      "set_need_status" ->
        apply_command(:set_need_status, args, actor, server)

      "link_shelter_resource" ->
        apply_command(:link_shelter_resource, args, actor, server)

      "link_shelter_need" ->
        apply_command(:link_shelter_need, args, actor, server)

      "match_pets" ->
        Emergencias.command(:match_pets, %{}, actor, server) |> then(&{:result, &1})

      "confirm_pet_match" ->
        apply_command(:confirm_pet_match, args, actor, server)

      "register_shelter" ->
        apply_command(:register_shelter, args, actor, server)

      "check_shelter" ->
        apply_command(:check_shelter, args, actor, server)

      "register_entry" ->
        apply_command(:register_entry, args, actor, server)

      "register_exit" ->
        apply_command(:register_exit, args, actor, server)

      "summary" ->
        {:result, Emergencias.summary(server)}

      "zone_summary" ->
        list(:zone_summary, args, server)

      "activity_log" ->
        {:result, Emergencias.list(:activity_log, %{username: actor}, server)}

      _ ->
        {:result, {:error, :comando_desconocido}}
    end
  end

  defp connect([username, password | rest], server) do
    role = Enum.at(rest, 0, "ciudadano") |> String.downcase()
    zone = Enum.at(rest, 1, "sin_zona")

    role =
      case role do
        "voluntario" -> :voluntario
        "coordinador" -> :coordinador
        "administrador" -> :administrador
        _ -> :ciudadano
      end

    result = Emergencias.connect(username, password, role, zone, server)
    {:result, result, if(match?({:ok, _}, result), do: username, else: nil)}
  end

  defp connect(_, _), do: {:result, {:error, :uso_incorrecto}}

  defp apply_command(action, args, actor, server) do
    params = command_params(action, args)
    {:result, Emergencias.command(action, params, actor, server)}
  end

  defp command_params(:register_zone, [code, name, level | rest]),
    do: %{code: code, name: name, level: level, affected: integer(Enum.at(rest, 0, "0"))}

  defp command_params(:register_sector, [zone, code, name, level | rest]),
    do: %{
      zone: zone,
      code: code,
      name: name,
      level: level,
      affected: integer(Enum.at(rest, 0, "0"))
    }

  defp command_params(:register_point, [zone, sector, code, name | rest]),
    do: %{
      zone: zone,
      sector: sector,
      code: code,
      name: name,
      affected: integer(Enum.at(rest, 0, "0"))
    }

  defp command_params(:register_need, [type, quantity, priority, zone | description]),
    do: %{
      type: type,
      quantity: integer(quantity),
      priority: priority,
      zone: zone,
      description: Enum.join(description, " ")
    }

  defp command_params(:register_resource, [code, name, category, quantity, unit, zone | _]),
    do: %{
      code: code,
      name: name,
      category: category,
      quantity: integer(quantity),
      unit: unit,
      zone: zone
    }

  defp command_params(:assign_resource, [need, resource, quantity | _]),
    do: %{need: need, resource: resource, quantity: integer(quantity)}

  defp command_params(:transfer_resource, [resource, from, to, quantity | _]),
    do: %{resource: resource, from: from, to: to, quantity: integer(quantity)}

  defp command_params(:transfer_resource, [resource, to, quantity | _]),
    do: %{resource: resource, to: to, quantity: integer(quantity)}

  defp command_params(:adjust_resource, [code, direction, quantity | rest]),
    do: %{
      code: code,
      direction: direction,
      quantity: integer(quantity),
      reason: Enum.join(rest, " ")
    }

  defp command_params(:report_person, [document, name, zone, status | _]),
    do: %{document: document, name: name, zone: zone, status: status}

  defp command_params(:update_person_status, [document, status | _]),
    do: %{document: document, status: status}

  defp command_params(:send_message, [document | content]),
    do: %{document: document, content: Enum.join(content, " ")}

  defp command_params(:deliver_message, [id | _]), do: %{id: id}

  defp command_params(:report_pet, [
         kind,
         species,
         name,
         color,
         size,
         zone,
         contact | characteristics
       ]),
       do: %{
         kind: kind,
         species: species,
         name: name,
         color: color,
         size: size,
         zone: zone,
         contact: contact,
         characteristics: Enum.join(characteristics, " ")
       }

  defp command_params(:confirm_pet_match, [lost, found | _]), do: %{lost: lost, found: found}

  defp command_params(:register_shelter, [code, name, zone, capacity | _]),
    do: %{code: code, name: name, zone: zone, capacity: integer(capacity)}

  defp command_params(:check_shelter, [code | _]), do: %{code: code}

  defp command_params(action, [shelter, document | _])
       when action in [:register_entry, :register_exit],
       do: %{shelter: shelter, document: document}

  defp command_params(:zone_summary, [zone | _]), do: %{zone: zone}
  defp command_params(:set_need_status, [id, status | _]), do: %{id: id, status: status}

  defp command_params(:link_shelter_resource, [shelter, resource | _]),
    do: %{shelter: shelter, resource: resource}

  defp command_params(:link_shelter_need, [shelter, need | _]),
    do: %{shelter: shelter, need: need}

  defp command_params(_, _), do: %{}

  defp list(action, args, server) do
    filters =
      Enum.reduce(args, %{}, fn arg, acc ->
        case String.split(arg, "=", parts: 2) do
          [key, value] ->
            key =
              %{
                "zone" => :zone,
                "zona" => :zone,
                "status" => :status,
                "estado" => :status,
                "priority" => :priority,
                "prioridad" => :priority,
                "type" => :type,
                "tipo" => :type,
                "species" => :species,
                "especie" => :species
              }[String.downcase(key)]

            if key, do: Map.put(acc, key, value), else: acc

          _ ->
            Map.put(acc, :zone, arg)
        end
      end)

    {:result, Emergencias.list(action, filters, server)}
  end

  defp do_find_person([query | _], server),
    do: {:result, Emergencias.command(:find_person, %{query: query}, nil, server)}

  defp do_find_person(_, _), do: {:result, {:error, :uso_incorrecto}}

  defp integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> value
    end
  end

  defp tokenize(line) do
    Regex.scan(~r/"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|(\S+)/u, line)
    |> Enum.map(fn match ->
      captures = Enum.drop(match, 1)
      Enum.find(captures, "", &(&1 != nil and &1 != "")) || ""
    end)
  end

  defp display({:ok, value}),
    do: Util2.mostrar(inspect(value, pretty: true, limit: :infinity), :mensaje)

  defp display({:error, reason}), do: Util2.mostrar("Error: #{inspect(reason)}", :error)
end
