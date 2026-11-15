defmodule Emergencias.MixProject do
  use Mix.Project

  def project do
    [
      app: :emergencias,
      version: "2.0.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: [],
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Sistema de gestión de emergencias interactivo por terminal"
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto], mod: {Emergencias.Application, []}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
