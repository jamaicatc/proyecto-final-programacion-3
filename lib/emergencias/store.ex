defmodule Emergencias.Store do
  # Persistencia en archivo de texto (Base64 de termino Erlang).
  @moduledoc "Persistencia textual simple: una cabecera y un término Erlang en Base64."

  @header "# Emergencias Elixir - datos serializados en texto plano\n"

  def load(path, initial_state) do
    case File.read(path) do
      {:ok, contents} ->
        with [header, encoded] <- String.split(contents, "\n", parts: 2),
             true <- header <> "\n" == @header,
             {:ok, binary} <- Base.decode64(String.trim(encoded)),
             state when is_map(state) <- :erlang.binary_to_term(binary, [:safe]) do
          {:ok, state}
        else
          _ -> {:error, :archivo_invalido, initial_state}
        end

      {:error, :enoent} ->
        {:ok, initial_state}

      {:error, reason} ->
        {:error, reason, initial_state}
    end
  rescue
    _ -> {:error, :archivo_invalido, initial_state}
  end

  def save(path, state) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok ->
        contents = @header <> Base.encode64(:erlang.term_to_binary(state)) <> "\n"
        File.write(path, contents, [:binary, :sync])

      error ->
        error
    end
  end
end
