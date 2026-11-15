defmodule EmergenciasExtraTest do
  use ExUnit.Case, async: true

  alias Emergencias.Coordinator

  setup do
    path =
      Path.join(System.tmp_dir!(), "emergencias-extra-#{System.unique_integer([:positive])}.txt")

    {:ok, server} = Coordinator.start_link(path: path)

    on_exit(fn ->
      if Process.alive?(server), do: GenServer.stop(server)
      File.rm(path)
    end)

    %{server: server, path: path}
  end

  defp connect(server, username, role \\ :coordinador, zone \\ "centro") do
    Emergencias.connect(username, "clave", role, zone, server)
  end

  test "registro explícito de usuarios, permisos y login", %{server: server} do
    assert {:ok, %{username: "admin", role: :administrador}} =
             Emergencias.command(
               :register_user,
               %{
                 username: "admin",
                 password: "clave",
                 full_name: "Administradora",
                 role: "administrador",
                 zone: "centro"
               },
               nil,
               server
             )

    assert {:error, :identificador_duplicado} =
             Emergencias.command(
               :register_user,
               %{username: "admin", password: "otra", role: "administrador"},
               nil,
               server
             )

    assert {:error, :contrasena_incorrecta} =
             Emergencias.command(
               :login,
               %{username: "admin", password: "incorrecta"},
               nil,
               server
             )

    assert {:ok, _} =
             Emergencias.command(:login, %{username: "admin", password: "clave"}, nil, server)

    assert {:error, :permiso_denegado} =
             Emergencias.command(
               :register_user,
               %{username: "vol", password: "clave", role: "voluntario"},
               nil,
               server
             )

    assert {:ok, %{username: "vol", role: :voluntario}} =
             Emergencias.command(
               :register_user,
               %{username: "vol", password: "clave", role: "voluntario"},
               "admin",
               server
             )

    assert {:ok, users} = Emergencias.list(:list_users, %{}, server)
    assert length(users) == 2
  end

  test "zonas, sectores y puntos con estadísticas recursivas", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "centro", name: "Centro", level: "critico", affected: 10},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_sector,
               %{zone: "centro", code: "s1", name: "Sector 1", level: "alto", affected: 5},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_point,
               %{zone: "centro", sector: "s1", code: "p1", name: "Punto 1", affected: 2},
               "coord",
               server
             )

    assert {:error, :identificador_duplicado} =
             Emergencias.command(
               :register_zone,
               %{code: "centro", name: "X", level: "bajo"},
               "coord",
               server
             )

    assert {:ok, detail} = Emergencias.command(:zone_summary, %{zone: "centro"}, nil, server)
    assert detail.sector_affected == 7
  end

  test "necesidades: filtros y prioridad", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "centro", name: "Centro", level: "critico"},
               "coord",
               server
             )

    assert {:ok, %{id: "N001"}} =
             Emergencias.command(
               :register_need,
               %{type: "agua", quantity: 10, priority: "baja", zone: "centro"},
               "coord",
               server
             )

    assert {:ok, %{id: "N002"}} =
             Emergencias.command(
               :register_need,
               %{type: "alimentos", quantity: 5, priority: "critica", zone: "centro"},
               "coord",
               server
             )

    assert {:ok, [first | _]} = Emergencias.list(:list_needs, %{zone: "centro"}, server)
    assert first.id == "N002"
    assert {:ok, needs} = Emergencias.list(:list_needs, %{type: "agua"}, server)
    assert length(needs) == 1
    assert {:ok, needs2} = Emergencias.list(:list_needs, %{status: "pendiente"}, server)
    assert length(needs2) == 2
  end

  test "recursos: inventario, ajustes, transferencias y negativos", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "centro", name: "Centro", level: "critico"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_resource,
               %{
                 code: "R1",
                 name: "Agua",
                 category: "agua",
                 quantity: 100,
                 unit: "litros",
                 zone: "centro"
               },
               "coord",
               server
             )

    assert {:error, :inventario_insuficiente} =
             Emergencias.command(
               :adjust_resource,
               %{code: "R1", direction: "salida", quantity: 200},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :adjust_resource,
               %{code: "R1", direction: "salida", quantity: 30},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :transfer_resource,
               %{resource: "R1", from: "centro", to: "norte", quantity: 20},
               "coord",
               server
             )

    assert {:ok, resources} = Emergencias.list(:list_resources, %{}, server)
    assert Enum.any?(resources, &(&1.code == "R1-norte"))

    assert {:error, :cantidad_invalida} =
             Emergencias.command(
               :register_resource,
               %{code: "R2", name: "X", category: "x", quantity: -5, unit: "u", zone: "centro"},
               "coord",
               server
             )
  end

  test "asignación a necesidad atendida se rechaza", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "centro", name: "Centro", level: "critico"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_resource,
               %{
                 code: "R1",
                 name: "Agua",
                 category: "agua",
                 quantity: 50,
                 unit: "litros",
                 zone: "centro"
               },
               "coord",
               server
             )

    assert {:ok, %{id: "N001"}} =
             Emergencias.command(
               :register_need,
               %{type: "agua", quantity: 10, priority: "alta", zone: "centro"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :assign_resource,
               %{need: "N001", resource: "R1", quantity: 10},
               "coord",
               server
             )

    assert {:error, :necesidad_cerrada} =
             Emergencias.command(
               :assign_resource,
               %{need: "N001", resource: "R1", quantity: 1},
               "coord",
               server
             )
  end

  test "personas: búsqueda, mensajes, historial y transiciones", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "centro", name: "Centro", level: "critico"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :report_person,
               %{document: "123", name: "Ana", zone: "centro", status: "reportada", age: 30},
               "coord",
               server
             )

    assert {:error, :persona_ya_registrada} =
             Emergencias.command(
               :report_person,
               %{document: "123", name: "Ana2", zone: "centro"},
               "coord",
               server
             )

    assert {:ok, p} = Emergencias.command(:find_person, %{document: "123"}, nil, server)
    assert p.name == "Ana"
    assert {:ok, people} = Emergencias.list(:list_people, %{name: "Ana"}, server)
    assert length(people) == 1

    assert {:ok, _} =
             Emergencias.command(
               :send_message,
               %{document: "123", content: "Hola"},
               "coord",
               server
             )

    assert {:ok, msgs} = Emergencias.list(:list_messages, %{document: "123"}, server)
    assert length(msgs) == 1
    msg = hd(msgs)
    assert {:ok, _} = Emergencias.command(:deliver_message, %{id: msg.id}, "coord", server)

    assert {:error, :mensaje_ya_entregado} =
             Emergencias.command(:deliver_message, %{id: msg.id}, "coord", server)

    assert {:ok, _} =
             Emergencias.command(
               :update_person_status,
               %{document: "123", status: "localizada"},
               "coord",
               server
             )

    assert {:error, :estado_final_o_invalido} =
             Emergencias.command(
               :update_person_status,
               %{document: "123", status: "reportada"},
               "coord",
               server
             )

    assert {:ok, person} = Emergencias.command(:find_person, %{document: "123"}, nil, server)
    assert length(person.history) >= 2
  end

  test "mascotas: coincidencia y cierre doble", %{server: server} do
    assert {:ok, _} =
             Emergencias.command(
               :register_user,
               %{username: "admin", password: "clave", role: "administrador"},
               nil,
               server
             )

    assert {:ok, _} = Emergencias.connect("admin", "clave", :administrador, "centro", server)

    assert {:ok, _} =
             Emergencias.command(
               :register_user,
               %{username: "vol", password: "clave", role: "voluntario"},
               "admin",
               server
             )

    assert {:ok, _} = Emergencias.connect("vol", "clave", :voluntario, "centro", server)

    assert {:ok, _} =
             Emergencias.command(
               :report_pet,
               %{
                 kind: "lost",
                 species: "perro",
                 name: "Luna",
                 color: "negra",
                 size: "mediana",
                 zone: "centro"
               },
               "vol",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :report_pet,
               %{
                 kind: "found",
                 species: "perro",
                 name: "Luna",
                 color: "negra",
                 size: "mediana",
                 zone: "centro"
               },
               "vol",
               server
             )

    assert {:ok, [%{score: 5}]} = Emergencias.command(:match_pets, %{}, "vol", server)

    assert {:error, :permiso_denegado} =
             Emergencias.command(
               :confirm_pet_match,
               %{lost: "A001", found: "A002"},
               "vol",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_user,
               %{username: "coord", password: "clave", role: "coordinador"},
               "admin",
               server
             )

    assert {:ok, _} = Emergencias.connect("coord", "clave", :coordinador, "centro", server)

    assert {:ok, _} =
             Emergencias.command(
               :confirm_pet_match,
               %{lost: "A001", found: "A002"},
               "coord",
               server
             )

    assert {:error, :coincidencia_invalida_o_resuelta} =
             Emergencias.command(
               :confirm_pet_match,
               %{lost: "A001", found: "A002"},
               "coord",
               server
             )

    assert {:ok, pets} = Emergencias.list(:list_pets, %{status: "resuelta"}, server)
    assert length(pets) == 2
  end

  test "albergues: capacidad e ingreso/salida", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "norte", name: "Norte", level: "alto"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_shelter,
               %{code: "A1", name: "Albergue", zone: "norte", capacity: 1},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :report_person,
               %{document: "123", name: "Ana", zone: "norte", status: "localizada"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :report_person,
               %{document: "456", name: "Luis", zone: "norte", status: "localizada"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_entry,
               %{shelter: "A1", document: "123"},
               "coord",
               server
             )

    assert {:error, :albergue_sin_cupos} =
             Emergencias.command(
               :register_entry,
               %{shelter: "A1", document: "456"},
               "coord",
               server
             )

    assert {:ok, %{occupied: 1, available: 0}} =
             Emergencias.command(:check_shelter, %{code: "A1"}, nil, server)

    assert {:ok, _} =
             Emergencias.command(
               :register_exit,
               %{shelter: "A1", document: "123"},
               "coord",
               server
             )

    assert {:error, :persona_no_alojada} =
             Emergencias.command(
               :register_exit,
               %{shelter: "A1", document: "123"},
               "coord",
               server
             )

    assert {:ok, shelters} = Emergencias.list(:list_shelters, %{}, server)
    assert hd(shelters).code == "A1"
  end

  test "albergue: asociar recursos y necesidades", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "norte", name: "Norte", level: "alto"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_shelter,
               %{code: "A1", name: "Albergue", zone: "norte", capacity: 5},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_resource,
               %{
                 code: "R1",
                 name: "Agua",
                 category: "agua",
                 quantity: 10,
                 unit: "l",
                 zone: "norte"
               },
               "coord",
               server
             )

    assert {:ok, %{id: "N001"}} =
             Emergencias.command(
               :register_need,
               %{type: "agua", quantity: 5, priority: "alta", zone: "norte"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :link_shelter_resource,
               %{shelter: "A1", resource: "R1"},
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :link_shelter_need,
               %{shelter: "A1", need: "N001"},
               "coord",
               server
             )

    assert {:ok, s} = Emergencias.command(:check_shelter, %{code: "A1"}, nil, server)
    assert "R1" in s.resources
    assert "N001" in s.needs
  end

  test "validaciones: credenciales, roles y negativos", %{server: server} do
    assert {:ok, _} = Emergencias.connect("laura", "clave", :coordinador, "centro", server)

    assert {:error, :contrasena_incorrecta} =
             Emergencias.connect("laura", "otra", :ciudadano, "centro", server)

    assert {:error, :autenticacion_requerida} =
             Emergencias.command(
               :register_zone,
               %{code: "x", name: "X", level: "alto"},
               "nadie",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "y", name: "Y", level: "alto"},
               "laura",
               server
             )
  end

  test "persistencia: guardar y recuperar", %{path: path, server: server} do
    assert {:ok, _} = Emergencias.connect("admin", "clave", :administrador, "centro", server)

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "centro", name: "Centro", level: "medio"},
               "admin",
               server
             )

    GenServer.stop(server)
    {:ok, restored} = Coordinator.start_link(path: path)

    assert {:ok, %{zone: %{code: "centro"}}} =
             Emergencias.command(:zone_summary, %{zone: "centro"}, nil, restored)

    GenServer.stop(restored)
  end

  test "concurrencia: asignaciones simultáneas", %{server: server} do
    assert {:ok, _} = connect(server, "laura")

    assert {:ok, _} =
             Emergencias.command(
               :register_zone,
               %{code: "centro", name: "Centro", level: "critico"},
               "laura",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :register_resource,
               %{
                 code: "R1",
                 name: "Agua",
                 category: "agua",
                 quantity: 50,
                 unit: "litros",
                 zone: "centro"
               },
               "laura",
               server
             )

    assert {:ok, %{id: "N001"}} =
             Emergencias.command(
               :register_need,
               %{type: "agua", quantity: 30, priority: "critica", zone: "centro"},
               "laura",
               server
             )

    assert {:ok, %{id: "N002"}} =
             Emergencias.command(
               :register_need,
               %{type: "agua", quantity: 30, priority: "alta", zone: "centro"},
               "laura",
               server
             )

    results =
      Task.async_stream(
        ["N001", "N002"],
        fn need ->
          Emergencias.command(
            :assign_resource,
            %{need: need, resource: "R1", quantity: 30},
            "laura",
            server
          )
        end,
        max_concurrency: 2,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert {:ok, [%{quantity: 20}]} = Emergencias.list(:list_resources, %{}, server)
  end

  test "centros de apoyo: registro, inventario asociado y persistencia de ubicación", %{
    server: server
  } do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, %{code: "C1"}} =
             Emergencias.command(
               :register_center,
               %{code: "C1", name: "Centro Norte", zone: "norte"},
               "coord",
               server
             )

    assert {:error, :identificador_duplicado} =
             Emergencias.command(
               :register_center,
               %{code: "C1", name: "Duplicado"},
               "coord",
               server
             )

    assert {:ok, %{center: "C1"}} =
             Emergencias.command(
               :register_resource,
               %{
                 code: "R-C1",
                 name: "Agua",
                 category: "agua",
                 quantity: 10,
                 unit: "litros",
                 zone: "norte",
                 center: "C1"
               },
               "coord",
               server
             )

    assert {:error, :centro_no_encontrado} =
             Emergencias.command(
               :register_resource,
               %{
                 code: "R-X",
                 name: "Agua",
                 category: "agua",
                 quantity: 1,
                 unit: "litros",
                 center: "NO_EXISTE"
               },
               "coord",
               server
             )

    assert {:ok, [%{code: "C1"}]} = Emergencias.list(:list_centers, %{}, server)
  end

  test "mensajes conservan historial de estado", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :report_person,
               %{document: "DOC-1", name: "Persona", status: "reportada"},
               "coord",
               server
             )

    assert {:ok, message} =
             Emergencias.command(
               :send_message,
               %{document: "DOC-1", content: "Aviso familiar"},
               "coord",
               server
             )

    assert length(message.history) == 1

    assert {:ok, delivered} =
             Emergencias.command(:deliver_message, %{id: message.id}, "coord", server)

    assert length(delivered.history) == 2
    assert Enum.map(delivered.history, & &1.status) == [:entregado, :pendiente]
  end

  test "una persona no puede transicionar dos veces al mismo estado concurrentemente", %{
    server: server
  } do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :report_person,
               %{document: "DOC-2", name: "Persona", status: "reportada"},
               "coord",
               server
             )

    results =
      Task.async_stream(
        1..2,
        fn _ ->
          Emergencias.command(
            :update_person_status,
            %{document: "DOC-2", status: "localizada"},
            "coord",
            server
          )
        end,
        max_concurrency: 2,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
  end

  test "concurrencia: no resolver dos veces una mascota", %{server: server} do
    assert {:ok, _} = connect(server, "coord")

    assert {:ok, _} =
             Emergencias.command(
               :report_pet,
               %{
                 kind: "lost",
                 species: "perro",
                 name: "Luna",
                 color: "negra",
                 size: "mediana",
                 zone: "centro"
               },
               "coord",
               server
             )

    assert {:ok, _} =
             Emergencias.command(
               :report_pet,
               %{
                 kind: "found",
                 species: "perro",
                 name: "Luna",
                 color: "negra",
                 size: "mediana",
                 zone: "centro"
               },
               "coord",
               server
             )

    assert {:ok, _} = Emergencias.command(:match_pets, %{}, "coord", server)

    results =
      Task.async_stream(
        1..2,
        fn _ ->
          Emergencias.command(:confirm_pet_match, %{lost: "A001", found: "A002"}, "coord", server)
        end,
        max_concurrency: 2,
        ordered: false
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
  end
end
