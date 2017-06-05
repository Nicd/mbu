defmodule MBU.Mixfile do
  use Mix.Project

  def project do
    [app: :mbu,
     version: "1.0.0",
     elixir: "~> 1.4",
     name: "MBU: Mix Build Utilities",
     source_url: "https://github.com/Nicd/mbu",
     docs: [
       main: "readme",
       extras: ["README.md"]
     ],
     description: description(),
     package: package(),

     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  defp package do
    [
      name: :mbu,
      maintainers: ["Mikko Ahlroth <mikko.ahlroth@gmail.com>"],
      licenses: ["BSD 3-clause"],
      links: %{
        "GitHub" => "https://github.com/Nicd/mbu",
        "Docs" => "https://hexdocs.pm/mbu"
      }
    ]
  end

  defp description do
    """
    MBU is a collection of build utilities for Mix to make it easier to build your project,
    for example building the front end. It supports task dependencies and watching
    directories.
    """
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ex_doc, "~> 0.16.0", only: :dev},
      {:fs, "~> 3.4.0"}
    ]
  end
end
