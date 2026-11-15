# Al ejecutar `iex -S mix`, utilizar IEx como anfitrión de la interfaz
# evita que dos procesos compitan por la entrada estándar.
unless System.get_env("EMERGENCIAS_NO_CLI") == "1" do
  Emergencias.Terminal.start(group_leader: Process.group_leader())
end
