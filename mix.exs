defmodule MAVLink.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mavlink,
      version: "0.9.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :xmerl]],
      source_url: "https://github.com/robinhilliard/elixir-mavlink",
      consolidate_protocols: false,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "bench/support"]
  defp elixirc_paths(_), do: ["lib"]

  # See https://virviil.github.io/2016/10/26/elixir-testing-without-starting-supervision-tree/
  defp aliases do
    [
      test: "test --no-start",
      benchmark: "run --no-start bench/tcp_throughput.exs"
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
        # Dialect module generated using mix mavlink
        dialect: nil,
        # Default to ground station-ish system id
        system_id: 245,
        # Default to system control
        component_id: 250,
        connections: []
      ],
      mod: {MAVLink.Application, []},
      extra_applications: [:logger, :xmerl]
    ]
  end

  defp deps do
    [
      {:circuits_uart, "~> 1.5.0"},
      {:poolboy, "~> 1.5"},
      {:dialyzex, "~> 1.2.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.34.0", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "A Mix task to generate code from a MAVLink xml definition file,
    and an application that enables communication with other systems
    using the MAVLink 1.0 or 2.0 protocol over serial, UDP and TCP
    connections."
  end

  defp package() do
    [
      name: "mavlink",
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      exclude_patterns: [".DS_Store"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/beamuav/elixir-mavlink"},
      maintainers: ["Robin Hilliard"]
    ]
  end
end
