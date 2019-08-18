defmodule MAVLink.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mavlink,
      version: "0.2.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env == :prod,
      description: description(),
      package: package(),
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :xmerl]],
      source_url: "https://github.com/robinhilliard/elixir-mavlink"
    ]
  end
  
  
  defp aliases do
    [
      test: "test --no-start"
    ]
  end

  
  @doc """
  Override environment variables in config.exs e.g:
  
  config :mavlink, dialect: APM
  config :mavlink, system_id: 1
  config :mavlink, component_id: 1
  config :mavlink, connections: ["udp:192.168.0.10:14550"]
  """
  def application do
    [
      env: [
        dialect: nil,       # Dialect module generated using mix mavlink
        system_id: 255,     # Default to ground station
        component_id: 250,  # Default to system control
        connections: []
      ],
      mod: {MAVLink.Application, []},
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
