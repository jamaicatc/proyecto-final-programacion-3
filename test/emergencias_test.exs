defmodule EmergenciasTest do
  use ExUnit.Case, async: true

  alias Emergencias.Coordinator

  setup do
    path = Path.join(System.tmp_dir!(), "emergencias-#{System.unique_integer([:positive])}.txt")
    {:ok, server} = Coordinator.start_link(path: path)

    on_exit(fn ->
      if Process.alive?(server), do: GenServer.stop(server)
      File.rm(path)
    end)

    %{server: server, path: path}
  end

  test "registro automático, autenticación y roles", %{server: server} do
    assert {:ok, %{registrado: true, role: :coordinador}} =
             Emergencias.connect("laura", "clave", :coordinador, "centro", server)

    assert {:error, :contrasena_incorrecta} =
             Emergencias.connect("laura", "otra", :ciudadano, "centro", server)

    assert {:error, :autenticacion_requerida} =
             Emergencias.command(
               :register_zone,
               %{code: "x", name: "X", level: "alto"},
               "nadie",
               server
             )
  end

  test "las asignaciones concurrentes no superan el inventario", %{server: server} do
    assert {:ok, _} = Emergencias.connect("laura", "clave", :coordinador, "centro", server)

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

  test "el aforo del albergue nunca excede la capacidad", %{server: server} do
    assert {:ok, _} = Emergencias.connect("coord", "clave", :coordinador, "norte", server)

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
  end

  test "puntúa y confirma coincidencias de mascotas", %{server: server} do
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

    assert {:ok, [%{lost: "A001", found: "A002", score: 5}]} =
             Emergencias.command(:match_pets, %{}, "vol", server)

    assert {:error, :permiso_denegado} =
             Emergencias.command(
               :confirm_pet_match,
               %{lost: "A001", found: "A002"},
               "vol",
               server
             )
  end

  test "recupera el estado desde un archivo de texto", %{path: path, server: server} do
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
end
