defmodule MBU.Mixfile do
  use Mix.Project

  def project do
    [app: :mbu,
     version: "0.2.0",
     elixir: "~> 1.4",
     name: "MBU: Mix Build Utilities",
     source_url: "https://github.com/Nicd/mbu",
     docs: [
       main: "readme",
       extras: ["README.md"]
     ],


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
      {:ex_doc, "~> 0.15.0", only: :dev},
      {:fs, "~> 2.12.0"}
    ]
  end
end
