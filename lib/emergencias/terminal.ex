defmodule Emergencias.Terminal do
  @moduledoc """
  Interfaz de consola interactiva. Toda operación de dominio se delega a
  Emergencias.Coordinator; este módulo solo gestiona presentación y entrada.
  """
  alias Emergencias.Coordinator

  @menus %{
    1 =>
      {"GESTIÓN DE USUARIOS",
       [
         "Registrar usuario",
         "Iniciar sesión",
         "Cerrar sesión",
         "Consultar usuarios",
         "Consultar usuario conectado",
         "Volver al menú principal"
       ]},
    2 =>
      {"GESTIÓN DE ZONAS AFECTADAS",
       [
         "Registrar zona",
         "Registrar sector",
         "Registrar punto de atención",
         "Consultar zonas",
         "Consultar sectores",
         "Consultar puntos de atención",
         "Consultar estadísticas por zona",
         "Volver al menú principal"
       ]},
    3 =>
      {"GESTIÓN DE NECESIDADES",
       [
         "Registrar necesidad",
         "Consultar todas las necesidades",
         "Buscar necesidades por zona",
         "Buscar por prioridad",
         "Buscar por estado",
         "Asignar recursos a una necesidad",
         "Cambiar estado de una necesidad",
         "Cancelar necesidad",
         "Volver al menú principal"
       ]},
    4 =>
      {"GESTIÓN DE RECURSOS E INVENTARIO",
       [
         "Registrar recurso",
         "Consultar inventario",
         "Buscar por categoría",
         "Buscar por zona",
         "Registrar entrada",
         "Registrar salida",
         "Asignar recurso a necesidad",
         "Transferir recursos entre centros",
         "Consultar historial de movimientos",
         "Registrar centro de apoyo",
         "Consultar centros de apoyo",
         "Volver al menú principal"
       ]},
    5 =>
      {"GESTIÓN DE PERSONAS Y FAMILIARES",
       [
         "Registrar persona afectada",
         "Buscar por nombre",
         "Buscar por documento",
         "Buscar por zona",
         "Consultar por estado",
         "Actualizar estado",
         "Registrar mensaje familiar",
         "Consultar mensajes familiares",
         "Cambiar estado de entrega de mensajes",
         "Consultar historial de estados",
         "Volver al menú principal"
       ]},
    6 =>
      {"GESTIÓN DE MASCOTAS",
       [
         "Registrar mascota perdida",
         "Registrar mascota encontrada",
         "Consultar reportes",
         "Buscar por especie",
         "Buscar por zona",
         "Buscar posibles coincidencias",
         "Confirmar coincidencia",
         "Resolver reportes",
         "Volver al menú principal"
       ]},
    7 =>
      {"GESTIÓN DE ALBERGUES",
       [
         "Registrar albergue",
         "Consultar albergues",
         "Consultar capacidad disponible",
         "Registrar entrada de persona",
         "Registrar salida de persona",
         "Asociar recursos",
         "Consultar necesidades asociadas",
         "Mostrar ocupación",
         "Albergue con mayor ocupación",
         "Volver al menú principal"
       ]}
  }

  def start(opts \\ []) do
    Process.flag(:trap_exit, true)
    server = Keyword.get(opts, :server, Coordinator)
    banner()

    try do
      main_loop(%{server: server, actor: nil})
    catch
      :throw, :terminal_eof -> success("Entrada finalizada. Sistema cerrado.")
    end
  end

  defp banner do
    clear()
    line()
    centered("PLATAFORMA DE COORDINACIÓN Y ATENCIÓN DE EMERGENCIAS")
    line()
    success("Estado: SISTEMA ACTIVO")
    IO.puts("Procesos iniciados correctamente:")

    Enum.each(
      [
        "Gestor de usuarios",
        "Gestor de zonas",
        "Gestor de necesidades",
        "Gestor de recursos",
        "Gestor de personas",
        "Gestor de mascotas",
        "Gestor de albergues"
      ],
      &success("[OK] " <> &1)
    )

    IO.puts("")
  end

  defp main_loop(state) do
    line()
    centered("MENÚ PRINCIPAL")
    line()

    [
      "1. Gestión de usuarios",
      "2. Gestión de zonas afectadas",
      "3. Gestión de necesidades",
      "4. Gestión de recursos e inventario",
      "5. Gestión de personas y familiares",
      "6. Gestión de mascotas perdidas y encontradas",
      "7. Gestión de albergues",
      "8. Consultar estadísticas y reportes",
      "9. Demostración de concurrencia",
      "10. Guardar información",
      "11. Salir"
    ]
    |> Enum.each(&IO.puts/1)

    IO.puts("")
    IO.puts("Sesión: #{if state.actor, do: state.actor, else: "no iniciada"}")

    case choice("Seleccione una opción: ", 1..11) do
      1 ->
        submenu(1, state)
        main_loop(state_after_menu(state))

      2 ->
        submenu(2, state)
        main_loop(state)

      3 ->
        submenu(3, state)
        main_loop(state)

      4 ->
        submenu(4, state)
        main_loop(state)

      5 ->
        submenu(5, state)
        main_loop(state)

      6 ->
        submenu(6, state)
        main_loop(state)

      7 ->
        submenu(7, state)
        main_loop(state)

      8 ->
        reports(state)
        main_loop(state)

      9 ->
        concurrency_demo()
        pause()
        main_loop(state)

      10 ->
        save_now(state)
        main_loop(state)

      11 ->
        if confirm?("¿Desea salir del sistema?") do
          if state.actor, do: Emergencias.disconnect(state.actor, state.server)
          success("Sesión finalizada. Hasta pronto.")
        else
          main_loop(state)
        end
    end
  end

  # La sesión se mantiene en el proceso de interfaz; cada submenú devuelve el actor actualizado.
  defp state_after_menu(state) do
    %{state | actor: Process.get(:terminal_actor, state.actor)}
  end

  defp submenu(number, state) do
    {title, options} = Map.fetch!(@menus, number)
    menu_loop(number, title, options, state)
  end

  defp menu_loop(number, title, options, state) do
    line()
    centered(title)
    line()

    Enum.with_index(options, 1)
    |> Enum.each(fn {label, index} -> IO.puts("#{index}. #{label}") end)

    IO.puts("0. Volver")

    case choice("Seleccione una opción: ", 0..length(options)) do
      0 ->
        :ok

      selected when selected == length(options) ->
        :ok

      selected ->
        next_state = perform(number, selected, state)
        Process.put(:terminal_actor, next_state.actor)
        pause()
        menu_loop(number, title, options, next_state)
    end
  end

  defp perform(1, 1, state) do
    IO.puts("\nRegistro de usuario (el primer usuario puede registrarse como administrador).")
    username = ask("Nombre de usuario")
    password = ask("Contraseña")
    full_name = ask("Nombre completo")
    role = enum_input("Rol", ["ciudadano", "voluntario", "coordinador", "administrador"])
    zone = ask("Zona (código o sin_zona)")

    params = %{
      username: username,
      password: password,
      full_name: full_name,
      role: role,
      zone: zone
    }

    case Emergencias.command(:register_user, params, state.actor, state.server) do
      {:ok, result} ->
        success(
          "Usuario registrado: " <>
            Enum.map_join(result, ", ", fn {k, v} -> "#{key_label(k)}: #{format_value(v)}" end)
        )

        state

      error ->
        show(error)
        state
    end
  end

  defp perform(1, 2, state) do
    username = ask("Usuario")
    password = ask("Contraseña")

    case Emergencias.command(:login, %{username: username, password: password}, nil, state.server) do
      {:ok, result} ->
        success(
          "Autenticación correcta: " <>
            Enum.map_join(result, ", ", fn {k, v} -> "#{key_label(k)}: #{format_value(v)}" end)
        )

        %{state | actor: username}

      error ->
        show(error)
        state
    end
  end

  defp perform(1, 3, %{actor: nil} = state), do: warning("No hay una sesión iniciada.") && state

  defp perform(1, 3, state) do
    show(Emergencias.disconnect(state.actor, state.server))
    %{state | actor: nil}
  end

  defp perform(1, 4, state), do: call_list(:list_users, %{}, state)

  defp perform(1, 5, %{actor: nil} = state) do
    warning("No hay usuario conectado.")
    state
  end

  defp perform(1, 5, state) do
    show(Emergencias.command(:get_user, %{username: state.actor}, state.actor, state.server))
    state
  end

  defp perform(2, 1, state) do
    params = %{
      code: ask("Código"),
      name: ask("Nombre"),
      level: enum_input("Nivel", ["critico", "alto", "medio", "bajo"]),
      affected: ask_int("Personas afectadas", 0)
    }

    run(:register_zone, params, state)
  end

  defp perform(2, 2, state),
    do:
      run(
        :register_sector,
        %{
          zone: ask("Código de zona"),
          code: ask("Código de sector"),
          name: ask("Nombre"),
          level: enum_input("Nivel", ["critico", "alto", "medio", "bajo"]),
          affected: ask_int("Personas afectadas", 0)
        },
        state
      )

  defp perform(2, 3, state),
    do:
      run(
        :register_point,
        %{
          zone: ask("Zona"),
          sector: ask("Sector"),
          code: ask("Código del punto"),
          name: ask("Nombre"),
          affected: ask_int("Personas afectadas", 0)
        },
        state
      )

  defp perform(2, 4, state), do: call_list(:list_zones, %{}, state)

  defp perform(2, 5, state) do
    case Emergencias.list(:list_zones, %{}, state.server) do
      {:ok, zones} ->
        Enum.each(zones, fn z ->
          IO.puts("Zona #{z.code} - #{z.name}")

          Enum.each(z.sectors, fn {code, sector} ->
            IO.puts(
              "  Sector #{code}: #{sector.name} | nivel #{sector.level} | afectados #{sector.affected}"
            )
          end)
        end)

      error ->
        show(error)
    end

    state
  end

  defp perform(2, 6, state) do
    case Emergencias.list(:list_zones, %{}, state.server) do
      {:ok, zones} ->
        Enum.each(zones, fn z ->
          Enum.each(z.sectors, fn {sector_code, sector} ->
            IO.puts("Zona #{z.code} / Sector #{sector_code}")

            Enum.each(sector.points, fn {code, point} ->
              IO.puts("  Punto #{code}: #{point.name} | afectados #{point.affected}")
            end)
          end)
        end)

      error ->
        show(error)
    end

    state
  end

  defp perform(2, 7, state), do: run(:zone_summary, %{zone: ask("Código de zona")}, state)

  defp perform(3, 1, state),
    do:
      run(
        :register_need,
        %{
          type: ask("Tipo/categoría de necesidad"),
          description: ask("Descripción"),
          quantity: ask_int("Cantidad", 1),
          zone: ask("Zona"),
          priority: enum_input("Prioridad", ["baja", "media", "alta", "critica"])
        },
        state
      )

  defp perform(3, 2, state), do: call_list(:list_needs, %{}, state)
  defp perform(3, 3, state), do: call_list(:list_needs, %{zone: ask("Zona")}, state)

  defp perform(3, 4, state),
    do:
      call_list(
        :list_needs,
        %{priority: enum_input("Prioridad", ["baja", "media", "alta", "critica"])},
        state
      )

  defp perform(3, 5, state),
    do:
      call_list(
        :list_needs,
        %{
          status:
            enum_input("Estado", ["pendiente", "asignada", "en_atencion", "atendida", "cancelada"])
        },
        state
      )

  defp perform(3, 6, state),
    do:
      run(
        :assign_resource,
        %{
          need: ask("ID necesidad"),
          resource: ask("Código recurso"),
          quantity: ask_int("Cantidad", 1)
        },
        state
      )

  defp perform(3, 7, state),
    do:
      run(
        :set_need_status,
        %{
          id: ask("ID necesidad"),
          status:
            enum_input("Estado", ["pendiente", "asignada", "en_atencion", "atendida", "cancelada"])
        },
        state
      )

  defp perform(3, 8, state),
    do: run(:set_need_status, %{id: ask("ID necesidad"), status: "cancelada"}, state)

  defp perform(4, 1, state),
    do:
      run(
        :register_resource,
        %{
          code: ask("Código"),
          name: ask("Nombre"),
          category: ask("Categoría"),
          quantity: ask_int("Cantidad inicial", 0),
          unit: ask("Unidad"),
          zone: ask("Zona"),
          center: ask("Centro (vacío si no aplica)")
        },
        state
      )

  defp perform(4, 2, state), do: call_list(:list_resources, %{}, state)
  defp perform(4, 3, state), do: call_list(:list_resources, %{type: ask("Categoría")}, state)
  defp perform(4, 4, state), do: call_list(:list_resources, %{zone: ask("Zona")}, state)

  defp perform(4, 5, state),
    do:
      run(
        :adjust_resource,
        %{
          code: ask("Código recurso"),
          direction: "entrada",
          quantity: ask_int("Cantidad a ingresar", 1),
          reason: ask("Motivo")
        },
        state
      )

  defp perform(4, 6, state),
    do:
      run(
        :adjust_resource,
        %{
          code: ask("Código recurso"),
          direction: "salida",
          quantity: ask_int("Cantidad a retirar", 1),
          reason: ask("Motivo")
        },
        state
      )

  defp perform(4, 7, state),
    do:
      run(
        :assign_resource,
        %{
          need: ask("ID necesidad"),
          resource: ask("Código recurso"),
          quantity: ask_int("Cantidad", 1)
        },
        state
      )

  defp perform(4, 8, state),
    do:
      run(
        :transfer_resource,
        %{
          resource: ask("Código recurso"),
          from: ask("Origen"),
          to: ask("Centro destino"),
          quantity: ask_int("Cantidad", 1)
        },
        state
      )

  defp perform(4, 9, state), do: call_list(:list_movements, %{}, state)

  defp perform(4, 10, state),
    do:
      run(
        :register_center,
        %{code: ask("Código centro"), name: ask("Nombre"), zone: ask("Zona")},
        state
      )

  defp perform(4, 11, state), do: call_list(:list_centers, %{}, state)

  defp perform(5, 1, state),
    do:
      run(
        :report_person,
        %{
          document: ask("Documento"),
          name: ask("Nombre completo"),
          zone: ask("Zona"),
          status: "reportada",
          age: optional_int("Edad")
        },
        state
      )

  defp perform(5, 2, state),
    do: call_list(:list_people, %{name: ask("Nombre o parte del nombre")}, state)

  defp perform(5, 3, state), do: run(:find_person, %{document: ask("Documento")}, state)
  defp perform(5, 4, state), do: call_list(:list_people, %{zone: ask("Zona")}, state)

  defp perform(5, 5, state),
    do:
      call_list(
        :list_people,
        %{
          status:
            enum_input("Estado", [
              "sin_informacion",
              "reportada",
              "localizada",
              "trasladada",
              "en_albergue",
              "reunificada"
            ])
        },
        state
      )

  defp perform(5, 6, state),
    do:
      run(
        :update_person_status,
        %{
          document: ask("Documento"),
          status:
            enum_input("Nuevo estado", ["localizada", "trasladada", "en_albergue", "reunificada"])
        },
        state
      )

  defp perform(5, 7, state),
    do:
      run(
        :send_message,
        %{document: ask("Documento destinatario"), content: ask("Mensaje familiar")},
        state
      )

  defp perform(5, 8, state),
    do: call_list(:list_messages, %{document: ask("Documento (vacío para todos)")}, state)

  defp perform(5, 9, state), do: run(:deliver_message, %{id: ask("ID mensaje")}, state)

  defp perform(5, 10, state),
    do: run(:find_person, %{document: ask("Documento para consultar historial")}, state)

  defp perform(6, 1, state), do: pet_report("perdida", state)
  defp perform(6, 2, state), do: pet_report("encontrada", state)
  defp perform(6, 3, state), do: call_list(:list_pets, %{}, state)
  defp perform(6, 4, state), do: call_list(:list_pets, %{species: ask("Especie")}, state)
  defp perform(6, 5, state), do: call_list(:list_pets, %{zone: ask("Zona")}, state)

  defp perform(6, 6, %{actor: nil} = state) do
    warning("Debe iniciar sesión para buscar coincidencias.")
    state
  end

  defp perform(6, 6, state) do
    case Emergencias.command(:match_pets, %{}, state.actor, state.server) do
      {:ok, matches} ->
        if matches == [], do: warning("No se encontraron coincidencias.")

        Enum.each(matches, fn match ->
          percent = Float.round(match.score / 5 * 100, 1)

          IO.puts(
            "Perdida #{match.lost} ↔ Encontrada #{match.found} | similitud: #{percent}% (#{match.score}/5 atributos)"
          )
        end)

      error ->
        show(error)
    end

    state
  end

  defp perform(6, 7, state),
    do:
      run(
        :confirm_pet_match,
        %{lost: ask("ID reporte perdido"), found: ask("ID reporte encontrado")},
        state
      )

  defp perform(6, 8, state), do: call_list(:list_pets, %{status: "posible_coincidencia"}, state)

  defp perform(7, 1, state),
    do:
      run(
        :register_shelter,
        %{
          code: ask("Código"),
          name: ask("Nombre"),
          zone: ask("Zona"),
          capacity: ask_int("Capacidad", 1)
        },
        state
      )

  defp perform(7, 2, state), do: call_list(:list_shelters, %{}, state)
  defp perform(7, 3, state), do: run(:check_shelter, %{code: ask("Código albergue")}, state)

  defp perform(7, 4, state),
    do:
      run(
        :register_entry,
        %{shelter: ask("Código albergue"), document: ask("Documento persona")},
        state
      )

  defp perform(7, 5, state),
    do:
      run(
        :register_exit,
        %{shelter: ask("Código albergue"), document: ask("Documento persona")},
        state
      )

  defp perform(7, 6, state),
    do:
      run(
        :link_shelter_resource,
        %{shelter: ask("Código albergue"), resource: ask("Código recurso")},
        state
      )

  defp perform(7, 7, state) do
    case Emergencias.list(:list_shelters, %{}, state.server) do
      {:ok, shelters} ->
        Enum.each(shelters, fn shelter ->
          IO.puts(
            "#{shelter.code}: necesidades asociadas #{Enum.map_join(shelter.needs, ", ", &to_string/1)}"
          )
        end)

      error ->
        show(error)
    end

    state
  end

  defp perform(7, 8, state), do: call_list(:list_shelters, %{}, state, "Ocupación")

  defp perform(7, 9, state) do
    case Emergencias.list(:list_shelters, %{}, state.server) do
      {:ok, []} ->
        warning("No hay albergues registrados.")

      {:ok, shelters} ->
        s = Enum.max_by(shelters, &(&1.occupied / &1.capacity))
        success("Mayor ocupación: #{s.name} (#{s.occupied}/#{s.capacity})")

      error ->
        show(error)
    end

    state
  end

  defp perform(_, _, state), do: state

  defp pet_report(kind, state) do
    params = %{
      kind: kind,
      species: ask("Especie"),
      name: ask("Nombre (desconocido si no se sabe)"),
      color: ask("Color"),
      size: ask("Tamaño"),
      zone: ask("Zona"),
      contact: ask("Contacto"),
      characteristics: ask("Características")
    }

    run(:report_pet, params, state)
  end

  defp run(_action, _params, %{actor: nil} = state) do
    warning("Debe iniciar sesión desde Gestión de usuarios antes de realizar esta operación.")
    state
  end

  defp run(action, params, state) do
    show(Emergencias.command(action, params, state.actor, state.server))
    state
  end

  defp call_list(action, filters, state, label \\ nil) do
    case Emergencias.list(action, filters, state.server) do
      {:ok, rows} -> table(label || title_for(action), rows)
      error -> show(error)
    end

    state
  end

  defp reports(state) do
    case Emergencias.summary(state.server) do
      {:ok, data} ->
        line()
        centered("ESTADÍSTICAS Y REPORTES")
        line()
        IO.puts("Usuarios: #{data.users} (conectados: #{data.connected_users})")
        IO.puts("Zonas registradas: #{data.zones}")
        IO.puts("Personas afectadas reportadas por zonas: #{data.affected_people}")

        IO.puts(
          "Personas registradas: #{data.people.total} | localizadas/reunificadas: #{data.people.located}"
        )

        critical =
          case Emergencias.list(:list_needs, %{priority: "critica"}, state.server) do
            {:ok, needs} -> length(needs)
            _ -> 0
          end

        IO.puts(
          "Necesidades: #{data.needs.total} | pendientes: #{data.needs.pending} | críticas: #{critical}"
        )

        available_units =
          Enum.reduce(data.resources, 0, fn resource, acc -> acc + resource.quantity end)

        assigned_units =
          case Emergencias.list(:list_movements, %{}, state.server) do
            {:ok, movements} ->
              movements
              |> Enum.filter(&(&1.kind == :asignacion))
              |> Enum.reduce(0, &(&1.quantity + &2))

            _ ->
              0
          end

        IO.puts(
          "Unidades disponibles: #{available_units} | unidades asignadas (histórico): #{assigned_units}"
        )

        IO.puts("Recursos disponibles:")
        table("Inventario", data.resources)
        IO.puts("Mascotas reportadas: #{data.pets}; mensajes familiares: #{data.messages}")
        IO.puts("Albergues registrados: #{data.shelters}")

        case Emergencias.list(:list_shelters, %{}, state.server) do
          {:ok, shelters} ->
            capacity = Enum.reduce(shelters, 0, &(&1.capacity + &2))
            occupied = Enum.reduce(shelters, 0, &(&1.occupied + &2))
            percent = if capacity > 0, do: Float.round(occupied / capacity * 100, 1), else: 0.0
            available_shelters = Enum.count(shelters, &(&1.capacity > &1.occupied))
            IO.puts("Albergues con cupos: #{available_shelters}")
            IO.puts("Ocupación total de albergues: #{occupied}/#{capacity} (#{percent}%)")

          _ ->
            :ok
        end

        case Emergencias.list(:list_pets, %{}, state.server) do
          {:ok, pets} ->
            IO.puts(
              "Mascotas pendientes de resolución: #{Enum.count(pets, &(&1.status != :resuelta))}"
            )

          _ ->
            :ok
        end

      error ->
        show(error)
    end
  end

  defp concurrency_demo do
    IO.puts("\nDEMOSTRACIÓN DE CONCURRENCIA REAL (procesos + GenServer)")

    path =
      Path.join(
        System.tmp_dir!(),
        "emergencias_concurrency_#{System.unique_integer([:positive])}.txt"
      )

    name = Module.concat([Emergencias, "Demo", "Server#{System.unique_integer([:positive])}"])
    {:ok, pid} = Coordinator.start_link(name: name, path: path)

    try do
      {:ok, _} = Emergencias.connect("demo_admin", "demo", :administrador, "zona_demo", name)

      {:ok, _} =
        Emergencias.command(
          :register_resource,
          %{
            code: "AGUA",
            name: "Agua",
            category: "agua",
            quantity: 50,
            unit: "litros",
            zone: "zona_demo"
          },
          "demo_admin",
          name
        )

      IO.puts("Inventario inicial: 50 litros.")
      IO.puts("Proceso 1 solicita: 30 litros.")
      IO.puts("Proceso 2 solicita: 25 litros.")

      tasks = [
        Task.async(fn ->
          Emergencias.command(
            :adjust_resource,
            %{code: "AGUA", direction: "salida", quantity: 30, reason: "concurrencia"},
            "demo_admin",
            name
          )
        end),
        Task.async(fn ->
          Process.sleep(10)

          Emergencias.command(
            :adjust_resource,
            %{code: "AGUA", direction: "salida", quantity: 25, reason: "concurrencia"},
            "demo_admin",
            name
          )
        end)
      ]

      results = Enum.map(tasks, &Task.await(&1, 10_000))

      results
      |> Enum.with_index(1)
      |> Enum.each(fn
        {{:ok, _}, index} ->
          success("Resultado proceso #{index}: ASIGNACIÓN EXITOSA.")

        {{:error, :inventario_insuficiente}, index} ->
          warning("Resultado proceso #{index}: INVENTARIO INSUFICIENTE.")

        {{:error, reason}, index} ->
          error(
            "Resultado proceso #{index}: #{if is_atom(reason), do: atom_label(reason), else: inspect(reason)}"
          )
      end)

      {:ok, [%{quantity: final}]} = Emergencias.list(:list_resources, %{}, name)
      IO.puts("Inventario final: #{final} litros.")
      if final >= 0, do: success("Invariante verificada: no existe inventario negativo.")
    after
      GenServer.stop(pid)
      File.rm(path)
    end
  rescue
    exception -> error("No se pudo ejecutar la demostración: #{Exception.message(exception)}")
  end

  defp save_now(state) do
    # El comando :save atraviesa el coordinador y ejecuta Store.save/2.
    case Emergencias.command(:save, %{}, state.actor, state.server) do
      {:ok, :guardado} -> success("Información guardada correctamente en data/emergencias.txt.")
      error -> show(error)
    end
  end

  # Tabla vacia: muestra advertencia en espanol.
  defp table(title, []), do: warning("#{title}: sin registros.")

  defp table(title, rows) when is_list(rows) do
    visible =
      Enum.map(rows, fn row ->
        row
        |> Map.to_list()
        |> Enum.reject(fn {key, _} ->
          key in [
            :password_hash,
            :history,
            :people,
            :points,
            :sectors,
            :assigned
          ]
        end)
        |> Map.new()
      end)

    keys = visible |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()
    headers = Enum.map(keys, &key_label/1)

    rendered =
      Enum.map(visible, fn row ->
        Enum.map(keys, fn key -> format_value(Map.get(row, key, "")) end)
      end)

    widths =
      Enum.with_index(headers)
      |> Enum.map(fn {header, index} ->
        Enum.max([String.length(header) | Enum.map(rendered, &String.length(Enum.at(&1, index)))])
      end)

    IO.puts("\n#{title}")

    IO.puts(
      " " <> (Enum.zip_with(headers, widths, &String.pad_trailing(&1, &2)) |> Enum.join(" | "))
    )

    IO.puts("-" <> Enum.map_join(widths, "-+-", &String.duplicate("-", &1)))

    Enum.each(rendered, fn cells ->
      IO.puts(
        " " <> (Enum.zip_with(cells, widths, &String.pad_trailing(&1, &2)) |> Enum.join(" | "))
      )
    end)
  end

  defp table(title, other), do: show({:ok, %{title: title, data: other}})

  defp key_label(key) when is_binary(key), do: key

  defp key_label(key) when is_atom(key) do
    %{
      :username => "Usuario",
      :full_name => "Nombre completo",
      :role => "Rol",
      :zone => "Zona",
      :code => "Código",
      :name => "Nombre",
      :level => "Nivel de emergencia",
      :affected => "Personas afectadas",
      :sectors => "Sectores registrados",
      :points => "Puntos de atención",
      :created_at => "Fecha de registro",
      :id => "ID",
      :type => "Tipo",
      :description => "Descripción",
      :quantity => "Cantidad",
      :remaining => "Cantidad pendiente",
      :priority => "Prioridad",
      :status => "Estado",
      :reporter => "Reportado por",
      :assigned => "Asignaciones",
      :category => "Categoría",
      :unit => "Unidad",
      :location => "Ubicación",
      :center => "Centro",
      :capacity => "Capacidad",
      :occupied => "Ocupados",
      :people => "Personas",
      :resources => "Recursos",
      :needs => "Necesidades",
      :document => "Documento",
      :age => "Edad",
      :reference => "Referencia",
      :sender => "Remitente",
      :recipient => "Destinatario",
      :content => "Contenido",
      :at => "Fecha",
      :delivered_at => "Fecha de entrega",
      :kind => "Tipo de reporte",
      :species => "Especie",
      :characteristics => "Características",
      :color => "Color",
      :size => "Tamaño",
      :contact => "Contacto",
      :match => "Coincidencia",
      :lost => "Reporte perdido",
      :found => "Reporte encontrado",
      :score => "Similitud",
      :confirmed => "Confirmado",
      :actor => "Actor",
      :resource => "Recurso",
      :detail => "Detalle",
      :available => "Disponibles",
      :total => "Total",
      :connected_users => "Usuarios conectados",
      :users => "Usuarios",
      :zones => "Zonas",
      :messages => "Mensajes",
      :pets => "Mascotas",
      :shelters => "Albergues",
      :activities => "Actividades",
      :located => "Localizadas",
      :pending => "Pendientes",
      :movement => "Movimiento",
      :movements => "Movimientos",
      :sector_affected => "Personas afectadas (sectores)",
      :affected_people => "Personas afectadas",
      :centers => "Centros de apoyo",
      :connected => "Conectados",
      :from => "Origen",
      :to => "Destino",
      :history => "Historial",
      :matches => "Coincidencias",
      :need => "Necesidad",
      :shelter => "Albergue",
      :person => "Persona",
      :registrado => "Registrado"
    }[key] || key |> Atom.to_string() |> String.capitalize()
  end

  defp key_label(key), do: to_string(key)

  defp format_value(nil), do: ""
  defp format_value(value) when is_boolean(value), do: if(value, do: "Sí", else: "No")
  defp format_value(value) when is_atom(value), do: atom_label(value)
  defp format_value(value) when is_binary(value), do: format_date(value)
  defp format_value(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp format_value(value), do: inspect(value, limit: 5, printable_limit: 40)

  defp atom_label(:critico), do: "Crítico"
  defp atom_label(:critica), do: "Crítica"
  defp atom_label(:alto), do: "Alto"
  defp atom_label(:alta), do: "Alta"
  defp atom_label(:medio), do: "Medio"
  defp atom_label(:media), do: "Media"
  defp atom_label(:bajo), do: "Bajo"
  defp atom_label(:baja), do: "Baja"
  defp atom_label(:pendiente), do: "Pendiente"
  defp atom_label(:asignada), do: "Asignada"
  defp atom_label(:en_atencion), do: "En atención"
  defp atom_label(:atendida), do: "Atendida"
  defp atom_label(:cancelada), do: "Cancelada"
  defp atom_label(:sin_informacion), do: "Sin información"
  defp atom_label(:reportada), do: "Reportada"
  defp atom_label(:localizada), do: "Localizada"
  defp atom_label(:trasladada), do: "Trasladada"
  defp atom_label(:en_albergue), do: "En albergue"
  defp atom_label(:reunificada), do: "Reunificada"
  defp atom_label(:perdida), do: "Perdida"
  defp atom_label(:encontrada), do: "Encontrada"
  defp atom_label(:entrada), do: "Entrada"
  defp atom_label(:salida), do: "Salida"
  defp atom_label(:asignacion), do: "Asignación"
  defp atom_label(:transferencia_salida), do: "Transferencia (salida)"
  defp atom_label(:transferencia_entrada), do: "Transferencia (entrada)"
  defp atom_label(:administrador), do: "Administrador"
  defp atom_label(:coordinador), do: "Coordinador"
  defp atom_label(:voluntario), do: "Voluntario"
  defp atom_label(:ciudadano), do: "Ciudadano"
  defp atom_label(:activa), do: "Activa"
  defp atom_label(:resuelta), do: "Resuelta"
  defp atom_label(:posible_coincidencia), do: "Posible coincidencia"
  defp atom_label(:entregado), do: "Entregado"
  defp atom_label(:desconectado), do: "Desconectado"
  defp atom_label(:guardado), do: "Guardado"
  defp atom_label(other), do: other |> Atom.to_string() |> String.capitalize()

  defp format_date(value) when is_binary(value) do
    case Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}:\d{2}))?/, value) do
      [_, y, m, d] -> "#{d}/#{m}/#{y}"
      [_, y, m, d, t] -> "#{d}/#{m}/#{y} #{t}"
      _ -> value
    end
  end

  defp show({:ok, value}) when is_list(value), do: table("Resultado", value)

  defp show({:ok, value}) when is_map(value),
    do: render_detail("RESULTADO DE LA OPERACIÓN", value)

  defp show({:ok, value}) when is_atom(value), do: success(atom_label(value))
  defp show({:ok, value}), do: success(to_string(value))
  defp show({:error, reason}), do: error("Operación rechazada: #{human_error(reason)}")
  defp show(other), do: IO.puts(inspect(other, pretty: true, limit: :infinity))

  defp render_detail(title, map) when is_map(map) do
    line()
    centered(title)
    line()
    render_map(map, 0)
  end

  defp render_map(map, indent) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.reject(fn {key, _} -> key in [:password_hash] end)
    |> Enum.each(fn {key, value} ->
      prefix = String.duplicate("  ", indent)

      cond do
        is_map(value) and not is_struct(value) ->
          IO.puts("#{prefix}#{key_label(key)}:")
          render_map(value, indent + 1)

        is_list(value) and Enum.all?(value, &is_map/1) ->
          IO.puts("#{prefix}#{key_label(key)}: #{length(value)} registro(s)")

        is_list(value) ->
          IO.puts("#{prefix}#{key_label(key)}: #{Enum.map_join(value, ", ", &format_value/1)}")

        match?(%MapSet{}, value) ->
          IO.puts("#{prefix}#{key_label(key)}: #{MapSet.size(value)}")

        true ->
          IO.puts("#{prefix}#{key_label(key)}: #{format_value(value)}")
      end
    end)
  end

  defp human_error(reason) do
    %{
      :autenticacion_requerida => "Debe iniciar sesión.",
      :permiso_denegado => "Su rol no tiene permisos para esta operación.",
      :inventario_insuficiente => "No hay cantidad suficiente en inventario.",
      :albergue_sin_cupos => "El albergue no tiene capacidad disponible.",
      :identificador_duplicado => "El código ya existe.",
      :primer_usuario_debe_ser_administrador =>
        "El primer usuario debe crearse con rol administrador.",
      :usuario_no_conectado => "No hay una sesión activa.",
      :contrasena_incorrecta => "Contraseña incorrecta.",
      :usuario_no_encontrado => "Usuario no encontrado.",
      :credenciales_invalidas => "Credenciales inválidas.",
      :rol_invalido => "Rol inválido.",
      :archivo_invalido => "El archivo de datos no es válido.",
      :enoent => "No se encontró el archivo de datos.",
      :persistencia => "No se pudo guardar la información.",
      :resultado_invalido => "El resultado de la operación no es válido.",
      :zona_no_encontrada => "Zona no encontrada.",
      :zona_o_sector_no_encontrado => "Zona o sector no encontrados.",
      :nivel_invalido => "El nivel de emergencia no es válido.",
      :datos_zona_invalidos => "Los datos de la zona son inválidos.",
      :datos_sector_invalidos => "Los datos del sector son inválidos.",
      :datos_punto_invalidos => "Los datos del punto de atención son inválidos.",
      :datos_centro_invalidos => "Los datos del centro son inválidos.",
      :datos_persona_invalidos => "Los datos de la persona son inválidos.",
      :datos_albergue_invalidos => "Los datos del albergue son inválidos.",
      :identificador_duplicado_o_zona_invalida => "El código ya existe o la zona no es válida.",
      :centro_no_encontrado => "Centro de apoyo no encontrado.",
      :necesidad_no_encontrada => "Necesidad no encontrada.",
      :necesidad_cerrada => "La necesidad ya está cerrada.",
      :necesidad_o_recurso_no_encontrado => "Necesidad o recurso no encontrados.",
      :tipo_necesidad_invalido => "El tipo de necesidad no es válido.",
      :prioridad_invalida => "La prioridad no es válida.",
      :estado_invalido => "El estado indicado no es válido.",
      :estado_final_o_invalido => "El estado final no es válido.",
      :transicion_invalida => "La transición de estado no es válida.",
      :cantidad_invalida => "La cantidad debe ser mayor que cero.",
      :cantidad_supera_necesidad => "La cantidad supera lo que resta de la necesidad.",
      :asignacion_invalida => "La asignación no es válida.",
      :recurso_no_encontrado => "Recurso no encontrado.",
      :recurso_invalido => "El recurso no es válido.",
      :inventario_insuficiente_o_tipo_incompatible =>
        "Inventario insuficiente o tipo de recurso incompatible.",
      :movimiento_invalido => "El movimiento no es válido.",
      :transferencia_invalida => "La transferencia no es válida.",
      :transferencia_invalida_o_inventario_insuficiente =>
        "Transferencia inválida o inventario insuficiente.",
      :persona_no_encontrada => "Persona no encontrada.",
      :persona_ya_registrada => "La persona ya está registrada.",
      :persona_no_alojada => "La persona no está alojada en ese albergue.",
      :mensaje_no_encontrado => "Mensaje no encontrado.",
      :mensaje_vacio => "El mensaje no puede estar vacío.",
      :mensaje_ya_entregado => "El mensaje ya fue entregado.",
      :reporte_no_encontrado => "Reporte no encontrado.",
      :reporte_mascota_invalido => "El reporte de mascota no es válido.",
      :coincidencia_invalida => "La coincidencia no es válida.",
      :coincidencia_invalida_o_resuelta => "La coincidencia no es válida o ya fue resuelta.",
      :albergue_no_encontrado => "Albergue no encontrado.",
      :albergue_o_necesidad_no_encontrada => "Albergue o necesidad no encontrados.",
      :albergue_o_persona_no_encontrado => "Albergue o persona no encontrados.",
      :albergue_o_recurso_no_encontrado => "Albergue o recurso no encontrados.",
      :asociacion_invalida => "La asociación no es válida.",
      :operacion_albergue_invalida => "La operación del albergue no es válida.",
      :operacion_desconocida => "Operación desconocida."
    }[reason] || inspect(reason)
  end

  defp choice(prompt, range) do
    value = ask(prompt)

    case Integer.parse(value) do
      {n, ""} ->
        if n in range do
          n
        else
          error("Ingrese una opción válida (#{Enum.min(range)} a #{Enum.max(range)}).")
          choice(prompt, range)
        end

      _ ->
        error("Ingrese una opción válida (#{Enum.min(range)} a #{Enum.max(range)}).")
        choice(prompt, range)
    end
  end

  def ask(label) when is_binary(label), do: ask(label, :standard_io)

  def ask(label, device) when is_binary(label) do
    ask_input(label, device)
  end

  def ask(device, label) when is_binary(label) do
    ask_input(label, device)
  end

  defp ask_input(label, device) do
    device = normalize_device(device)

    case IO.gets(device, "#{label}: ") do
      :eof -> throw(:terminal_eof)
      {:error, _reason} -> throw(:terminal_eof)
      value when is_binary(value) -> String.trim(value)
      value -> value |> to_string() |> String.trim()
    end
  end

  defp normalize_device(device) when is_pid(device), do: device

  defp normalize_device(device) when device in [:standard_io, :stdio, :user, :standard_error],
    do: device

  defp normalize_device(nil), do: :standard_io

  defp normalize_device(device) when is_atom(device) do
    case Process.whereis(device) do
      nil -> :standard_io
      pid -> pid
    end
  end

  defp normalize_device(device), do: device

  defp ask_int(label, min) do
    value = ask(label)

    case Integer.parse(value) do
      {n, ""} when n >= min ->
        n

      _ ->
        error("Ingrese un entero mayor o igual a #{min}.")
        ask_int(label, min)
    end
  end

  defp optional_int(label) do
    value = ask(label <> " (opcional)")

    case Integer.parse(value) do
      {n, ""} when n >= 0 ->
        n

      _ when value == "" ->
        nil

      _ ->
        error("Edad inválida.")
        optional_int(label)
    end
  end

  defp enum_input(label, values) do
    value = String.downcase(ask(label <> " [#{Enum.join(values, "/")}]"))

    if value in values do
      value
    else
      error("Valor permitido: #{Enum.join(values, ", ")}")
      enum_input(label, values)
    end
  end

  defp confirm?(question), do: String.downcase(ask(question <> " (s/n)")) in ["s", "si", "sí"]

  defp pause,
    do:
      (
        IO.gets("\nPresione Enter para continuar...")
        :ok
      )

  defp clear, do: if(IO.ANSI.enabled?(), do: IO.write("\e[2J\e[H"), else: :ok)
  defp line, do: IO.puts(String.duplicate("=", 64))
  defp centered(text), do: IO.puts("             " <> text)
  defp success(text), do: styled(text, "\e[32m", :stdio)
  defp warning(text), do: styled(text, "\e[33m", :stdio)
  defp error(text), do: styled(text, "\e[31m", :stderr)

  defp styled(text, code, device) do
    output = if IO.ANSI.enabled?(), do: "#{code}#{text}\e[0m", else: text
    if device == :stderr, do: IO.puts(:standard_error, output), else: IO.puts(output)
  end

  defp title_for(:list_zones), do: "LISTADO DE ZONAS AFECTADAS"
  defp title_for(:list_needs), do: "LISTADO DE NECESIDADES"
  defp title_for(:list_resources), do: "INVENTARIO DE RECURSOS"
  defp title_for(:list_people), do: "LISTADO DE PERSONAS"
  defp title_for(:list_pets), do: "LISTADO DE MASCOTAS"
  defp title_for(:list_shelters), do: "LISTADO DE ALBERGUES"
  defp title_for(:list_centers), do: "LISTADO DE CENTROS DE APOYO"
  defp title_for(:list_messages), do: "MENSAJES FAMILIARES"
  defp title_for(:list_movements), do: "HISTORIAL DE MOVIMIENTOS"
  defp title_for(:list_users), do: "LISTADO DE USUARIOS"
  defp title_for(:zone_summary), do: "ESTADÍSTICAS POR ZONA"

  defp title_for(other),
    do: other |> Atom.to_string() |> String.upcase() |> String.replace("_", " ")
end
