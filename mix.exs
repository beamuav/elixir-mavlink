defmodule Mavlink.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mavlink,
      version: "0.2.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :xmerl]],
      source_url: "https://github.com/robinhilliard/elixir-mavlink"
    ]
  end


  def application do
    [
      env: [system: 255, component: 250],
      mod: {Mavlink.Application, []},
      extra_applications: [:logger]
    ]
  end


  defp deps do
    [
      {:circuits_uart, "~> 1.3"},
      {:dialyzex, "~> 1.2.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.20.2", only: :dev, runtime: false}
    ]
  end

  
  defp description() do
    "A Mix task to generate code from a MAVLink xml definition file, and an application that enables communication with other systems using the MAVLink 1.0 or 2.0 protocol over serial, UDP and TCP connections."
  end
  
  
  defp package() do
    [
      name: "mavlink",
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/robinhilliard/elixir-mavlink"},
      maintainers: ["Robin Hilliard"]
    ]
  end
  
end
