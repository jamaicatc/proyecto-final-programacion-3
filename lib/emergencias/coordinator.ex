defmodule Emergencias.Coordinator do
  @moduledoc """
  Estado coordinado del sistema. El GenServer serializa transacciones que
  modifican recursos, necesidades y albergues, garantizando sus invariantes.
  """
  use GenServer

  alias Emergencias.Store

  @roles [:ciudadano, :voluntario, :coordinador, :administrador]
  @priorities %{baja: 1, media: 2, alta: 3, critica: 4, crítica: 4}
  @need_states [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]
  @person_states [
    :sin_informacion,
    :reportada,
    :localizada,
    :trasladada,
    :en_albergue,
    :reunificada
  ]

  def start_link(opts \\ []) do
    if Keyword.has_key?(opts, :name) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  def command(server \\ __MODULE__, action, params \\ %{}),
    do: GenServer.call(server, {:command, action, params}, 30_000)

  # Estado inicial vacio del sistema.
  def initial_state do
    %{
      users: %{},
      connected: MapSet.new(),
      zones: %{},
      needs: %{},
      resources: %{},
      centers: %{},
      shelters: %{},
      people: %{},
      messages: %{},
      pets: %{},
      activities: [],
      movements: [],
      matches: [],
      counters: %{need: 0, person: 0, message: 0, pet: 0}
    }
  end

  @impl true
  def init(opts) do
    path =
      Keyword.get(
        opts,
        :path,
        Application.get_env(:emergencias, :data_path, "data/emergencias.txt")
      )

    {:ok, state} =
      case Store.load(path, initial_state()) do
        {:ok, loaded} -> {:ok, Map.merge(initial_state(), loaded)}
        {:error, _, initial} -> {:ok, initial}
      end

    {:ok,
     %{data: state |> Map.put_new(:centers, %{}) |> Map.put(:connected, MapSet.new()), path: path}}
  end

  @impl true
  def handle_call({:command, action, params}, _from, %{data: data, path: path} = state) do
    outcome = execute(action, params, data)

    case outcome do
      {{:ok, _value} = result, new_data} ->
        case Store.save(path, new_data) do
          :ok -> {:reply, result, %{state | data: new_data}}
          {:error, reason} -> {:reply, {:error, {:persistencia, reason}}, state}
        end

      {{:error, _reason} = result, _unchanged_data} ->
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      other ->
        {:reply, {:error, {:resultado_invalido, other}}, state}
    end
  end

  defp execute(:register_user, params, data) do
    username = text(Map.get(params, :username))
    password = Map.get(params, :password)
    role = normalize_atom(Map.get(params, :role, :ciudadano))
    zone = text(Map.get(params, :zone, "sin_zona"))
    full_name = text(Map.get(params, :full_name, username))
    actor = Map.get(params, :actor)

    cond do
      not valid_text?(username) or not valid_text?(password) ->
        error(:credenciales_invalidas)

      Map.has_key?(data.users, username) ->
        error(:identificador_duplicado)

      role not in @roles ->
        error(:rol_invalido)

      map_size(data.users) == 0 and role != :administrador ->
        error(:primer_usuario_debe_ser_administrador)

      map_size(data.users) > 0 and
          not (is_binary(actor) and MapSet.member?(data.connected, actor) and
                   data.users[actor].role == :administrador) ->
        error(:permiso_denegado)

      true ->
        user = %{
          username: username,
          password_hash: password_hash(password),
          full_name: if(full_name == "", do: username, else: full_name),
          role: role,
          zone: if(zone == "", do: "sin_zona", else: zone),
          created_at: now()
        }

        next =
          put_in(data.users[username], user)
          |> activity(actor || username, {:register_user, username})

        {{:ok, Map.take(user, [:username, :full_name, :role, :zone])}, next}
    end
  end

  defp execute(:login, %{username: username, password: password}, data) do
    case data.users[username] do
      nil ->
        error(:usuario_no_encontrado)

      user ->
        if secure_equal?(user.password_hash, password) do
          next =
            put_in(data.connected, MapSet.put(data.connected, username))
            |> activity(username, :connect)

          {{:ok, Map.take(user, [:username, :role, :zone])}, next}
        else
          error(:contrasena_incorrecta)
        end
    end
  end

  defp execute(:connect, %{username: username, password: password} = params, data) do
    role = normalize_atom(Map.get(params, :role, :ciudadano))
    zone = text(Map.get(params, :zone, "sin_zona"))
    full_name = text(Map.get(params, :full_name, username))
    full_name = if full_name == "", do: username, else: full_name

    cond do
      not valid_text?(username) or not valid_text?(password) ->
        error(:credenciales_invalidas)

      role not in @roles ->
        error(:rol_invalido)

      user = data.users[username] ->
        if secure_equal?(user.password_hash, password) do
          next =
            put_in(data.connected, MapSet.put(data.connected, username))
            |> activity(username, :connect)

          {{:ok, %{username: username, role: user.role, zone: user.zone}}, next}
        else
          error(:contrasena_incorrecta)
        end

      true ->
        user = %{
          username: username,
          password_hash: password_hash(password),
          full_name: full_name,
          role: role,
          zone: zone,
          created_at: now()
        }

        next =
          put_in(data.users[username], user)
          |> put_in([:connected], MapSet.put(data.connected, username))

        {{:ok, %{username: username, role: role, zone: zone, registrado: true}},
         activity(next, username, :connect)}
    end
  end

  defp execute(:disconnect, %{username: username}, data) do
    if MapSet.member?(data.connected, username) do
      {{:ok, :desconectado},
       %{data | connected: MapSet.delete(data.connected, username)}
       |> activity(username, :disconnect)}
    else
      error(:usuario_no_conectado)
    end
  end

  defp execute(:register_zone, params, data) do
    with {:ok, actor} <- authorized(data, params, [:coordinador, :administrador]),
         code when is_binary(code) and byte_size(code) > 0 <-
           text(Map.get(params, :code, Map.get(params, :codigo))),
         false <- Map.has_key?(data.zones, code),
         level when level in [:critico, :alto, :medio, :bajo] <-
           normalize_atom(Map.get(params, :level, Map.get(params, :nivel))),
         {:ok, affected} <- nonnegative(Map.get(params, :affected, Map.get(params, :personas, 0))) do
      zone = %{
        code: code,
        name: text(Map.get(params, :name, Map.get(params, :nombre, code))),
        level: level,
        affected: affected,
        sectors: %{},
        created_at: now()
      }

      success(activity(put_in(data.zones[code], zone), actor, {:register_zone, code}), zone)
    else
      true -> error(:identificador_duplicado)
      nil -> error(:nivel_invalido)
      {:error, _} = err -> err
      _ -> error(:datos_zona_invalidos)
    end
  end

  defp execute(:register_sector, params, data) do
    with {:ok, actor} <- authorized(data, params, [:coordinador, :administrador]),
         zone_code <- text(Map.get(params, :zone, Map.get(params, :zona))),
         %{} = zone <- data.zones[zone_code],
         code when is_binary(code) and byte_size(code) > 0 <-
           text(Map.get(params, :code, Map.get(params, :codigo))),
         false <- Map.has_key?(zone.sectors, code),
         level when level in [:critico, :alto, :medio, :bajo] <-
           normalize_atom(Map.get(params, :level, Map.get(params, :nivel))),
         {:ok, affected} <- nonnegative(Map.get(params, :affected, 0)) do
      sector = %{
        code: code,
        name: text(Map.get(params, :name, code)),
        level: level,
        affected: affected,
        points: %{}
      }

      next = put_in(data.zones[zone_code].sectors[code], sector)
      success(activity(next, actor, {:register_sector, code}), sector)
    else
      nil -> error(:zona_no_encontrada)
      true -> error(:identificador_duplicado)
      {:error, _} = err -> err
      _ -> error(:datos_sector_invalidos)
    end
  end

  defp execute(:register_point, params, data) do
    zone_code = text(Map.get(params, :zone, Map.get(params, :zona)))
    sector_code = text(Map.get(params, :sector))
    code = text(Map.get(params, :code, Map.get(params, :codigo)))

    with {:ok, actor} <- authorized(data, params, [:coordinador, :administrador]),
         %{} = sector <- get_in(data.zones, [zone_code, :sectors, sector_code]),
         code when is_binary(code) and byte_size(code) > 0 <- code,
         false <- Map.has_key?(sector.points, code),
         {:ok, affected} <- nonnegative(Map.get(params, :affected, 0)) do
      point_success(data, zone_code, sector_code, code, params, actor, affected)
    else
      nil -> error(:zona_o_sector_no_encontrado)
      true -> error(:identificador_duplicado)
      {:error, _} = err -> err
      _ -> error(:datos_punto_invalidos)
    end
  end

  defp execute(:register_need, params, data) do
    with {:ok, actor} <- authenticated(data, params),
         {:ok, quantity} <- positive(Map.get(params, :quantity, Map.get(params, :cantidad))),
         {:ok, priority} <- priority(Map.get(params, :priority, Map.get(params, :prioridad))),
         type when is_binary(type) and byte_size(type) > 0 <-
           text(Map.get(params, :type, Map.get(params, :tipo))),
         zone <- text(Map.get(params, :zone, Map.get(params, :zona))),
         true <- Map.has_key?(data.zones, zone) or zone == "sin_zona" do
      {id, next} = next_id(data, :need, "N")

      need = %{
        id: id,
        type: type,
        description: text(Map.get(params, :description, Map.get(params, :descripcion, ""))),
        quantity: quantity,
        remaining: quantity,
        zone: zone,
        priority: priority,
        status: :pendiente,
        reporter: actor,
        assigned: [],
        created_at: now()
      }

      success(activity(put_in(next.needs[id], need), actor, {:register_need, id}), need)
    else
      false -> error(:zona_no_encontrada)
      {:error, _} = err -> err
      _ -> error(:tipo_necesidad_invalido)
    end
  end

  # Centros de apoyo: catálogo explícito para ubicar inventario y controlar transferencias.
  defp execute(:register_center, params, data) do
    with {:ok, actor} <- authorized(data, params, [:coordinador, :administrador]),
         code when is_binary(code) and byte_size(code) > 0 <-
           text(Map.get(params, :code, Map.get(params, :codigo))),
         false <- Map.has_key?(data.centers, code),
         name when is_binary(name) and byte_size(name) > 0 <-
           text(Map.get(params, :name, Map.get(params, :nombre))),
         zone <- text(Map.get(params, :zone, Map.get(params, :zona, "sin_zona"))) do
      center = %{code: code, name: name, zone: zone, created_at: now()}

      success(
        activity(put_in(data.centers[code], center), actor, {:register_center, code}),
        center
      )
    else
      true -> error(:identificador_duplicado)
      {:error, _} = err -> err
      _ -> error(:datos_centro_invalidos)
    end
  end

  defp execute(:list_centers, _params, data), do: {{:ok, Map.values(data.centers)}, data}

  defp execute(:register_resource, params, data) do
    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         code when is_binary(code) and byte_size(code) > 0 <-
           text(Map.get(params, :code, Map.get(params, :codigo))),
         false <- Map.has_key?(data.resources, code),
         {:ok, quantity} <- nonnegative(Map.get(params, :quantity, Map.get(params, :cantidad))),
         zone <- text(Map.get(params, :zone, Map.get(params, :zona, "sin_zona"))),
         center <- text(Map.get(params, :center, Map.get(params, :centro, ""))),
         true <- center == "" or Map.has_key?(data.centers, center) do
      resource = %{
        code: code,
        name: text(Map.get(params, :name, Map.get(params, :nombre, code))),
        category: text(Map.get(params, :category, Map.get(params, :categoria, "general"))),
        quantity: quantity,
        unit: text(Map.get(params, :unit, Map.get(params, :unidad, "unidades"))),
        location: text(Map.get(params, :location, Map.get(params, :ubicacion, zone))),
        zone: zone,
        center: center
      }

      next = put_in(data.resources[code], resource)
      next = movement(next, actor, code, :entrada, quantity, "registro inicial")
      success(activity(next, actor, {:register_resource, code}), resource)
    else
      true -> error(:identificador_duplicado)
      false -> error(:centro_no_encontrado)
      {:error, _} = err -> err
      _ -> error(:recurso_invalido)
    end
  end

  defp execute(:adjust_resource, params, data) do
    code = text(Map.get(params, :code))

    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         %{} = resource <- data.resources[code],
         {:ok, quantity} <- positive(Map.get(params, :quantity)),
         direction when direction in [:entrada, :salida] <-
           normalize_atom(Map.get(params, :direction)) do
      current = resource.quantity

      if direction == :salida and current < quantity do
        error(:inventario_insuficiente)
      else
        updated = %{
          resource
          | quantity: current + if(direction == :entrada, do: quantity, else: -quantity)
        }

        next =
          put_in(data.resources[code], updated)
          |> movement(actor, code, direction, quantity, text(Map.get(params, :reason, "ajuste")))

        success(activity(next, actor, {:adjust_resource, code}), updated)
      end
    else
      nil -> error(:recurso_no_encontrado)
      {:error, _} = err -> err
      _ -> error(:movimiento_invalido)
    end
  end

  defp execute(:assign_resource, params, data) do
    need_id = text(Map.get(params, :need, Map.get(params, :need_id)))
    resource_id = text(Map.get(params, :resource, Map.get(params, :resource_id)))

    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         %{} = need <- data.needs[need_id],
         %{} = resource <- data.resources[resource_id],
         {:ok, quantity} <- positive(Map.get(params, :quantity, Map.get(params, :cantidad))),
         true <- need.status not in [:atendida, :cancelada],
         true <- need.remaining >= quantity,
         true <- resource.quantity >= quantity,
         true <- need.type == resource.category or need.type == resource.name do
      revised_need = %{
        need
        | remaining: need.remaining - quantity,
          status: if(need.remaining == quantity, do: :atendida, else: :asignada),
          assigned: [%{resource: resource_id, quantity: quantity, at: now()} | need.assigned]
      }

      revised_resource = %{resource | quantity: resource.quantity - quantity}

      next =
        data
        |> put_in([:needs, need_id], revised_need)
        |> put_in([:resources, resource_id], revised_resource)

      next =
        movement(next, actor, resource_id, :asignacion, quantity, need_id)
        |> activity(actor, {:assign_resource, need_id, resource_id})

      success(next, %{need: revised_need, resource: revised_resource})
    else
      nil ->
        error(:necesidad_o_recurso_no_encontrado)

      false ->
        cond do
          data.needs[need_id] && data.needs[need_id].status in [:atendida, :cancelada] ->
            error(:necesidad_cerrada)

          data.needs[need_id] &&
              data.needs[need_id].remaining <
                (Map.get(params, :quantity) || Map.get(params, :cantidad) || 0) ->
            error(:cantidad_supera_necesidad)

          data.resources[resource_id] ->
            error(:inventario_insuficiente_o_tipo_incompatible)

          true ->
            error(:asignacion_invalida)
        end

      {:error, _} = err ->
        err

      _ ->
        error(:asignacion_invalida)
    end
  end

  defp execute(:set_need_status, params, data) do
    id = text(Map.get(params, :id))
    status = normalize_atom(Map.get(params, :status))

    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         %{} = need <- data.needs[id],
         true <- status in @need_states,
         true <- valid_need_transition?(need.status, status) do
      updated = %{need | status: status}

      success(
        activity(put_in(data.needs[id], updated), actor, {:need_status, id, status}),
        updated
      )
    else
      nil -> error(:necesidad_no_encontrada)
      false -> error(:transicion_invalida)
      {:error, _} = err -> err
      _ -> error(:estado_invalido)
    end
  end

  defp execute(:register_shelter, params, data) do
    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         code when is_binary(code) and byte_size(code) > 0 <-
           text(Map.get(params, :code, Map.get(params, :codigo))),
         false <- Map.has_key?(data.shelters, code),
         {:ok, capacity} <- positive(Map.get(params, :capacity, Map.get(params, :capacidad))),
         zone <- text(Map.get(params, :zone, Map.get(params, :zona, "sin_zona"))) do
      shelter = %{
        code: code,
        name: text(Map.get(params, :name, Map.get(params, :nombre, code))),
        zone: zone,
        capacity: capacity,
        occupied: 0,
        people: MapSet.new(),
        resources: [],
        needs: []
      }

      success(
        activity(put_in(data.shelters[code], shelter), actor, {:register_shelter, code}),
        shelter
      )
    else
      true -> error(:identificador_duplicado_o_zona_invalida)
      false -> error(:zona_no_encontrada)
      {:error, _} = err -> err
      _ -> error(:datos_albergue_invalidos)
    end
  end

  defp execute(:register_entry, params, data), do: shelter_entry(params, data, :entry)
  defp execute(:register_exit, params, data), do: shelter_entry(params, data, :exit)

  defp execute(:report_person, params, data) do
    with {:ok, actor} <- authenticated(data, params),
         document when is_binary(document) and byte_size(document) > 0 <-
           text(Map.get(params, :document, Map.get(params, :documento))),
         false <- Map.has_key?(data.people, document),
         status when status in @person_states <-
           normalize_atom(Map.get(params, :status, Map.get(params, :estado, :reportada))),
         zone <- text(Map.get(params, :zone, Map.get(params, :zona, "sin_zona"))) do
      {id, next} = next_id(data, :person, "P")

      person = %{
        id: id,
        document: document,
        name: text(Map.get(params, :name, Map.get(params, :nombre, "Sin nombre"))),
        age: Map.get(params, :age),
        zone: zone,
        status: status,
        history: [%{status: status, at: now(), by: actor}],
        reference: text(Map.get(params, :reference, ""))
      }

      success(
        activity(put_in(next.people[document], person), actor, {:report_person, document}),
        person
      )
    else
      true -> error(:persona_ya_registrada)
      {:error, _} = err -> err
      _ -> error(:datos_persona_invalidos)
    end
  end

  defp execute(:update_person_status, params, data) do
    document = text(Map.get(params, :document, Map.get(params, :documento)))
    status = normalize_atom(Map.get(params, :status, Map.get(params, :estado)))

    with {:ok, actor} <- authenticated(data, params),
         %{} = person <- data.people[document],
         true <- status in @person_states,
         true <- valid_person_transition?(person.status, status) do
      updated = %{
        person
        | status: status,
          history: [%{status: status, at: now(), by: actor} | person.history]
      }

      success(
        activity(
          put_in(data.people[document], updated),
          actor,
          {:person_status, document, status}
        ),
        updated
      )
    else
      nil -> error(:persona_no_encontrada)
      false -> error(:estado_final_o_invalido)
      {:error, _} = err -> err
      _ -> error(:estado_invalido)
    end
  end

  defp execute(:send_message, params, data) do
    document = text(Map.get(params, :document, Map.get(params, :destinatario)))

    with {:ok, actor} <- authenticated(data, params),
         %{} <- data.people[document],
         content when is_binary(content) and byte_size(content) > 0 <-
           text(Map.get(params, :content, Map.get(params, :contenido))) do
      {id, next} = next_id(data, :message, "M")

      message = %{
        id: id,
        document: document,
        sender: actor,
        recipient: document,
        content: content,
        status: :pendiente,
        at: now(),
        history: [%{status: :pendiente, at: now(), by: actor}]
      }

      success(activity(put_in(next.messages[id], message), actor, {:send_message, id}), message)
    else
      nil -> error(:persona_no_encontrada)
      {:error, _} = err -> err
      _ -> error(:mensaje_vacio)
    end
  end

  defp execute(:deliver_message, params, data) do
    id = text(Map.get(params, :id))

    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         %{} = message <- data.messages[id],
         :pendiente <- message.status do
      delivered_at = now()

      updated =
        message
        |> Map.put(:status, :entregado)
        |> Map.put(:delivered_at, delivered_at)
        |> Map.update(
          :history,
          [%{status: :entregado, at: delivered_at, by: actor}],
          &[%{status: :entregado, at: delivered_at, by: actor} | &1]
        )

      success(
        activity(put_in(data.messages[id], updated), actor, {:deliver_message, id}),
        updated
      )
    else
      nil -> error(:mensaje_no_encontrado)
      _ -> error(:mensaje_ya_entregado)
    end
  end

  defp execute(:report_pet, params, data) do
    with {:ok, actor} <- authenticated(data, params),
         kind when kind in [:perdida, :encontrada, :lost, :found] <-
           normalize_atom(Map.get(params, :kind, Map.get(params, :type, Map.get(params, :tipo)))),
         species when is_binary(species) and byte_size(species) > 0 <-
           text(Map.get(params, :species, Map.get(params, :especie))) do
      {id, next} = next_id(data, :pet, "A")
      kind = if kind in [:lost, :perdida], do: :perdida, else: :encontrada

      pet = %{
        id: id,
        kind: kind,
        species: species,
        name: text(Map.get(params, :name, Map.get(params, :nombre, "desconocido"))),
        characteristics:
          text(Map.get(params, :characteristics, Map.get(params, :caracteristicas, ""))),
        color: text(Map.get(params, :color, "")),
        size: text(Map.get(params, :size, Map.get(params, :tamano, ""))),
        zone: text(Map.get(params, :zone, Map.get(params, :zona, "sin_zona"))),
        contact: text(Map.get(params, :contact, Map.get(params, :contacto, ""))),
        status: :activa,
        match: nil,
        reporter: actor,
        created_at: now()
      }

      success(activity(put_in(next.pets[id], pet), actor, {:report_pet, id}), pet)
    else
      {:error, _} = err -> err
      _ -> error(:reporte_mascota_invalido)
    end
  end

  defp execute(:match_pets, params, data) do
    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]) do
      pets = Map.values(data.pets)

      candidates =
        for lost <- pets,
            lost.kind == :perdida,
            lost.status == :activa,
            found <- pets,
            found.kind == :encontrada,
            found.status == :activa,
            score = pet_score(lost, found),
            score >= 3,
            do: %{lost: lost.id, found: found.id, score: score}

      updated =
        Enum.reduce(candidates, data, fn match, acc ->
          acc
          |> update_in([:pets, match.lost], &%{&1 | status: :posible_coincidencia})
          |> update_in([:pets, match.found], &%{&1 | status: :posible_coincidencia})
        end)

      updated = %{
        updated
        | matches: Enum.uniq_by(candidates ++ updated.matches, &{&1.lost, &1.found})
      }

      success(activity(updated, actor, :match_pets), candidates)
    else
      {:error, _} = err -> err
    end
  end

  defp execute(:confirm_pet_match, params, data) do
    lost_id = text(Map.get(params, :lost))
    found_id = text(Map.get(params, :found))

    with {:ok, actor} <- authorized(data, params, [:coordinador, :administrador]),
         %{} = lost <- data.pets[lost_id],
         %{} = found <- data.pets[found_id],
         true <- lost.kind == :perdida and found.kind == :encontrada,
         true <- lost.status != :resuelta and found.status != :resuelta do
      match = %{
        lost: lost_id,
        found: found_id,
        score: pet_score(lost, found),
        confirmed: true,
        at: now()
      }

      next =
        data
        |> update_in([:pets, lost_id], &%{&1 | status: :resuelta, match: found_id})
        |> update_in([:pets, found_id], &%{&1 | status: :resuelta, match: lost_id})

      success(
        activity(
          %{next | matches: [match | next.matches]},
          actor,
          {:confirm_pet_match, lost_id, found_id}
        ),
        match
      )
    else
      nil -> error(:reporte_no_encontrado)
      false -> error(:coincidencia_invalida_o_resuelta)
      {:error, _} = err -> err
      _ -> error(:coincidencia_invalida)
    end
  end

  defp execute(:transfer_resource, params, data) do
    code = text(Map.get(params, :resource, Map.get(params, :code)))
    from = text(Map.get(params, :from, Map.get(params, :origen)))
    to = text(Map.get(params, :to, Map.get(params, :destino)))

    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         %{} = resource <- data.resources[code],
         {:ok, quantity} <- positive(Map.get(params, :quantity, Map.get(params, :cantidad))),
         true <- resource.quantity >= quantity,
         true <-
           from == "" or resource.location == from or resource.zone == from or
             Map.get(resource, :center, "") == from,
         true <- to != "" and to != from do
      destination_code = code <> "-" <> String.replace(to, " ", "_")
      destination_center = if Map.has_key?(data.centers, to), do: to, else: ""
      destination_zone = if destination_center != "", do: data.centers[to].zone, else: to

      destination_resource =
        Map.get(data.resources, destination_code, %{
          resource
          | code: destination_code,
            quantity: 0,
            location: to,
            zone: destination_zone,
            center: destination_center
        })

      destination_resource =
        destination_resource
        |> Map.put(:quantity, destination_resource.quantity + quantity)
        |> Map.put(:location, to)
        |> Map.put(:zone, destination_zone)
        |> Map.put(:center, destination_center)

      source = %{resource | quantity: resource.quantity - quantity}

      next =
        data
        |> put_in([:resources, code], source)
        |> put_in([:resources, destination_code], destination_resource)
        |> movement(actor, code, :transferencia_salida, quantity, to)
        |> movement(actor, destination_code, :transferencia_entrada, quantity, code)

      success(activity(next, actor, {:transfer_resource, code, destination_code}), %{
        from: source,
        to: destination_resource
      })
    else
      nil -> error(:recurso_no_encontrado)
      false -> error(:transferencia_invalida_o_inventario_insuficiente)
      {:error, _} = err -> err
      _ -> error(:transferencia_invalida)
    end
  end

  defp execute(:list_needs, params, data) do
    results =
      data.needs
      |> Map.values()
      |> filter(:zone, Map.get(params, :zone, Map.get(params, :zona)))
      |> filter(:type, Map.get(params, :type, Map.get(params, :tipo)))
      |> filter(:status, Map.get(params, :status, Map.get(params, :estado)))
      |> filter(:priority, Map.get(params, :priority, Map.get(params, :prioridad)))
      |> Enum.sort_by(&{-Map.get(@priorities, &1.priority, 0), &1.created_at})

    {{:ok, results}, data}
  end

  defp execute(:pending_needs, _params, data) do
    results =
      data.needs
      |> Map.values()
      |> Enum.filter(&(&1.status in [:pendiente, :asignada, :en_atencion]))
      |> Enum.sort_by(&{-Map.get(@priorities, &1.priority, 0), &1.created_at})

    {{:ok, results}, data}
  end

  defp execute(:list_resources, params, data) do
    results =
      data.resources
      |> Map.values()
      |> filter(:zone, Map.get(params, :zone, Map.get(params, :zona)))
      |> filter(:category, Map.get(params, :type, Map.get(params, :tipo)))

    {{:ok, results}, data}
  end

  defp execute(:critical_resources, _params, data) do
    {{:ok, Enum.filter(Map.values(data.resources), &(&1.quantity > 0))}, data}
  end

  defp execute(:list_people, params, data) do
    results =
      data.people
      |> Map.values()
      |> filter(:zone, Map.get(params, :zone, Map.get(params, :zona)))
      |> filter(:status, Map.get(params, :status, Map.get(params, :estado)))
      |> maybe_filter(:name, Map.get(params, :name, Map.get(params, :nombre)))
      |> maybe_filter(:document, Map.get(params, :document, Map.get(params, :documento)))

    {{:ok, results}, data}
  end

  defp execute(:find_person, params, data) do
    value = text(Map.get(params, :document, Map.get(params, :query)))

    result =
      Enum.find_value(data.people, fn {document, person} ->
        if document == value or
             String.contains?(String.downcase(person.name), String.downcase(value)),
           do: person
      end)

    if result, do: {{:ok, result}, data}, else: error(:persona_no_encontrada)
  end

  defp execute(:list_messages, params, data) do
    document = Map.get(params, :document, Map.get(params, :destinatario))

    results =
      data.messages |> Map.values() |> maybe_filter(:document, document) |> Enum.sort_by(& &1.at)

    {{:ok, results}, data}
  end

  defp execute(:list_pets, params, data) do
    results =
      data.pets
      |> Map.values()
      |> filter(:species, Map.get(params, :species, Map.get(params, :especie)))
      |> filter(:zone, Map.get(params, :zone, Map.get(params, :zona)))
      |> filter(:status, Map.get(params, :status, Map.get(params, :estado)))

    {{:ok, results}, data}
  end

  defp execute(:check_shelter, params, data) do
    code = text(Map.get(params, :code, Map.get(params, :codigo)))

    case data.shelters[code] do
      nil -> error(:albergue_no_encontrado)
      shelter -> {{:ok, Map.put(shelter, :available, shelter.capacity - shelter.occupied)}, data}
    end
  end

  defp execute(:list_shelters, _params, data) do
    {{:ok, Enum.sort_by(Map.values(data.shelters), &(-&1.occupied / &1.capacity))}, data}
  end

  defp execute(:list_movements, _params, data) do
    {{:ok, Enum.sort_by(data.movements, & &1.at, :desc)}, data}
  end

  defp execute(:link_shelter_resource, params, data) do
    code = text(Map.get(params, :shelter, Map.get(params, :code)))
    resource = text(Map.get(params, :resource))

    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         %{} <- data.shelters[code],
         %{} <- data.resources[resource] do
      updated = update_in(data.shelters[code].resources, &Enum.uniq([resource | &1]))

      success(
        activity(updated, actor, {:link_shelter_resource, code, resource}),
        updated.shelters[code]
      )
    else
      nil -> error(:albergue_o_recurso_no_encontrado)
      {:error, _} = err -> err
      _ -> error(:asociacion_invalida)
    end
  end

  defp execute(:link_shelter_need, params, data) do
    code = text(Map.get(params, :shelter, Map.get(params, :code)))
    need = text(Map.get(params, :need))

    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         %{} <- data.shelters[code],
         %{} <- data.needs[need] do
      updated = update_in(data.shelters[code].needs, &Enum.uniq([need | &1]))
      success(activity(updated, actor, {:link_shelter_need, code, need}), updated.shelters[code])
    else
      nil -> error(:albergue_o_necesidad_no_encontrada)
      {:error, _} = err -> err
      _ -> error(:asociacion_invalida)
    end
  end

  defp execute(:list_zones, _params, data) do
    {{:ok, Map.values(data.zones)}, data}
  end

  defp execute(:zone_summary, params, data) do
    code = text(Map.get(params, :zone, Map.get(params, :codigo)))

    case data.zones[code] do
      nil ->
        error(:zona_no_encontrada)

      zone ->
        sector_people = recursive_affected(Map.values(zone.sectors))

        result = %{
          zone: zone,
          sector_affected: sector_people,
          needs: Enum.count(data.needs, fn {_, n} -> n.zone == code end),
          resources: Enum.filter(Map.values(data.resources), &(&1.zone == code)),
          shelters: Enum.filter(Map.values(data.shelters), &(&1.zone == code))
        }

        {{:ok, result}, data}
    end
  end

  defp execute(:summary, _params, data) do
    result = %{
      users: map_size(data.users),
      connected_users: MapSet.size(data.connected),
      zones: map_size(data.zones),
      affected_people: recursive_sum(Map.values(data.zones), :affected),
      needs: %{
        total: map_size(data.needs),
        pending:
          recursive_count(Map.values(data.needs), fn n ->
            n.status in [:pendiente, :asignada, :en_atencion]
          end)
      },
      resources:
        Enum.map(
          Map.values(data.resources),
          &Map.take(&1, [:code, :name, :quantity, :unit, :zone])
        ),
      people: %{
        total: map_size(data.people),
        located:
          recursive_count(Map.values(data.people), fn p ->
            p.status in [:localizada, :en_albergue, :reunificada]
          end)
      },
      messages: map_size(data.messages),
      pets: map_size(data.pets),
      shelters: map_size(data.shelters),
      activities: length(data.activities)
    }

    {{:ok, result}, data}
  end

  defp execute(:save, _params, data), do: {{:ok, :guardado}, data}

  defp execute(:list_users, _params, data) do
    users =
      data.users
      |> Map.values()
      |> Enum.map(&Map.take(&1, [:username, :full_name, :role, :zone, :created_at]))

    {{:ok, users}, data}
  end

  defp execute(:get_user, params, data) do
    username = text(Map.get(params, :username, Map.get(params, :actor)))

    case data.users[username] do
      nil -> error(:usuario_no_encontrado)
      user -> {{:ok, Map.take(user, [:username, :full_name, :role, :zone])}, data}
    end
  end

  defp execute(:activity_log, params, data) do
    actor = Map.get(params, :username, Map.get(params, :actor))

    entries =
      if actor, do: Enum.filter(data.activities, &(&1.actor == actor)), else: data.activities

    {{:ok, entries}, data}
  end

  defp execute(_action, _params, data), do: {error(:operacion_desconocida), data}

  # La búsqueda recursiva acumula personas afectadas a través de sectores y puntos.
  defp recursive_affected([]), do: 0

  defp recursive_affected([%{affected: count, points: points} | rest]),
    do: count + recursive_points(Map.values(points)) + recursive_affected(rest)

  defp recursive_points([]), do: 0
  defp recursive_points([%{affected: count} | rest]), do: count + recursive_points(rest)

  # Funciones recursivas adicionales para conteo y suma sobre listas.
  defp recursive_count([], _predicate), do: 0

  defp recursive_count([head | tail], predicate),
    do: if(predicate.(head), do: 1, else: 0) + recursive_count(tail, predicate)

  defp recursive_sum([], _field), do: 0

  defp recursive_sum([head | tail], field),
    do: Map.get(head, field, 0) + recursive_sum(tail, field)

  defp pet_score(a, b) do
    Enum.count(
      [
        a.species == b.species,
        same?(a.color, b.color),
        same?(a.size, b.size),
        same?(a.zone, b.zone),
        a.name != "desconocido" and String.downcase(a.name) == String.downcase(b.name)
      ],
      & &1
    )
  end

  defp same?(a, b), do: a != "" and b != "" and String.downcase(a) == String.downcase(b)

  defp shelter_entry(params, data, action) do
    code = text(Map.get(params, :shelter, Map.get(params, :code)))
    document = text(Map.get(params, :document, Map.get(params, :documento)))

    with {:ok, actor} <- authorized(data, params, [:voluntario, :coordinador, :administrador]),
         %{} = shelter <- data.shelters[code],
         %{} = person <- data.people[document] do
      present? = MapSet.member?(shelter.people, document)
      person_status = if action == :entry, do: :en_albergue, else: :localizada

      cond do
        action == :entry and present? ->
          error(:persona_ya_registrada)

        action == :entry and shelter.occupied >= shelter.capacity ->
          error(:albergue_sin_cupos)

        action == :exit and not present? ->
          error(:persona_no_alojada)

        action == :entry and not valid_person_transition?(person.status, person_status) ->
          error(:transicion_invalida)

        action == :exit and not valid_person_transition?(person.status, person_status) ->
          error(:transicion_invalida)

        true ->
          members =
            if action == :entry,
              do: MapSet.put(shelter.people, document),
              else: MapSet.delete(shelter.people, document)

          updated = %{
            shelter
            | people: members,
              occupied: shelter.occupied + if(action == :entry, do: 1, else: -1)
          }

          person_next = update_person_status(data, person, person_status, actor)

          next =
            put_in(person_next.shelters[code], updated)
            |> activity(actor, {action, code, document})

          success(next, %{shelter: updated, person: next.people[document]})
      end
    else
      nil -> error(:albergue_o_persona_no_encontrado)
      {:error, _} = err -> err
      _ -> error(:operacion_albergue_invalida)
    end
  end

  defp authorized(data, params, roles) do
    with {:ok, actor} <- authenticated(data, params),
         %{role: role} <- data.users[actor],
         true <- role in roles do
      {:ok, actor}
    else
      false -> error(:permiso_denegado)
      {:error, _} = err -> err
      _ -> error(:autenticacion_requerida)
    end
  end

  defp authenticated(data, params) do
    actor = Map.get(params, :actor)

    if is_binary(actor) and MapSet.member?(data.connected, actor),
      do: {:ok, actor},
      else: error(:autenticacion_requerida)
  end

  defp update_person_status(data, person, status, actor) do
    updated = %{
      person
      | status: status,
        history: [%{status: status, at: now(), by: actor} | person.history]
    }

    put_in(data.people[person.document], updated)
  end

  defp activity(data, actor, action),
    do: %{data | activities: [%{actor: actor, action: action, at: now()} | data.activities]}

  defp movement(data, actor, code, kind, quantity, detail),
    do: %{
      data
      | movements: [
          %{
            actor: actor,
            resource: code,
            kind: kind,
            quantity: quantity,
            detail: detail,
            at: now()
          }
          | data.movements
        ]
    }

  defp next_id(data, counter, prefix) do
    value = data.counters[counter] + 1
    id = prefix <> String.pad_leading(Integer.to_string(value), 3, "0")
    {id, put_in(data.counters[counter], value)}
  end

  defp success(data, value), do: {{:ok, value}, data}
  defp error(reason), do: {:error, reason}
  defp text(nil), do: ""
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: String.trim(value)
  defp text(value), do: to_string(value)
  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace(" ", "_")

    known = %{
      "ciudadano" => :ciudadano,
      "voluntario" => :voluntario,
      "coordinador" => :coordinador,
      "administrador" => :administrador,
      "critico" => :critico,
      "crítico" => :critico,
      "critica" => :critica,
      "crítica" => :crítica,
      "alta" => :alta,
      "alto" => :alto,
      "media" => :media,
      "medio" => :medio,
      "baja" => :baja,
      "bajo" => :bajo,
      "pendiente" => :pendiente,
      "asignada" => :asignada,
      "en_atencion" => :en_atencion,
      "en_atención" => :en_atencion,
      "atendida" => :atendida,
      "cancelada" => :cancelada,
      "sin_informacion" => :sin_informacion,
      "sin_información" => :sin_informacion,
      "reportada" => :reportada,
      "localizada" => :localizada,
      "trasladada" => :trasladada,
      "en_albergue" => :en_albergue,
      "reunificada" => :reunificada,
      "perdida" => :perdida,
      "perdido" => :perdida,
      "encontrada" => :encontrada,
      "encontrado" => :encontrada,
      "lost" => :lost,
      "found" => :found,
      "entrada" => :entrada,
      "salida" => :salida,
      "asc" => :asc,
      "desc" => :desc,
      "activa" => :activa,
      "posible_coincidencia" => :posible_coincidencia,
      "resuelta" => :resuelta
    }

    Map.get(known, normalized)
  end

  defp normalize_atom(_), do: nil
  defp valid_text?(value), do: is_binary(value) and String.trim(value) != ""
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp secure_equal?(stored_hash, password) when is_binary(stored_hash) and is_binary(password),
    do: PluglessHash.secure_compare(stored_hash, password_hash(password))

  defp password_hash(password), do: :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)

  defp nonnegative(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp nonnegative(value) when is_binary(value), do: parse_integer(value, &(&1 >= 0))
  defp nonnegative(_), do: error(:cantidad_invalida)
  defp positive(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(value) when is_binary(value), do: parse_integer(value, &(&1 > 0))
  defp positive(_), do: error(:cantidad_invalida)

  defp parse_integer(value, predicate) do
    case Integer.parse(value) do
      {integer, ""} -> if predicate.(integer), do: {:ok, integer}, else: error(:cantidad_invalida)
      _ -> error(:cantidad_invalida)
    end
  end

  defp priority(value) do
    value = normalize_atom(value)

    if Map.has_key?(@priorities, value),
      do: {:ok, if(value in [:crítica, :critico], do: :critica, else: value)},
      else: error(:prioridad_invalida)
  end

  defp valid_need_transition?(from, to),
    do:
      from != to and from not in [:atendida, :cancelada] and
        (to != :pendiente or from == :pendiente)

  defp valid_person_transition?(from, to) do
    transitions = %{
      sin_informacion: [:reportada, :localizada, :trasladada, :en_albergue],
      reportada: [:localizada, :trasladada, :en_albergue, :reunificada],
      localizada: [:trasladada, :en_albergue, :reunificada],
      trasladada: [:localizada, :en_albergue, :reunificada],
      en_albergue: [:localizada, :trasladada, :reunificada],
      reunificada: []
    }

    from != to and to in Map.get(transitions, from, [])
  end

  defp filter(list, _key, nil), do: list

  defp filter(list, key, value) do
    Enum.filter(list, fn item ->
      actual = Map.get(item, key)
      expected = if is_atom(actual), do: normalize_atom(value), else: text(value)

      if is_binary(actual),
        do: String.downcase(actual) == String.downcase(expected || ""),
        else: actual == expected
    end)
  end

  defp maybe_filter(list, _key, nil), do: list

  defp maybe_filter(list, key, value) do
    query = value |> text() |> String.downcase()

    Enum.filter(list, fn item ->
      String.contains?(String.downcase(text(Map.get(item, key))), query)
    end)
  end

  defp point_success(data, zone, sector, code, params, actor, affected) do
    point = %{code: code, name: text(Map.get(params, :name, code)), affected: affected}
    next = put_in(data.zones[zone].sectors[sector].points[code], point)
    success(activity(next, actor, {:register_point, code}), point)
  end
end

defmodule PluglessHash do
  @moduledoc false
  def secure_compare(a, b) when byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  rescue
    _ -> a == b
  end

  def secure_compare(_, _), do: false
end
