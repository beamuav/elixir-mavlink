defmodule Mavlink.Mixfile do
  use Mix.Project

  def project do
    [app: :mavlink,
     version: "0.1.1",
     elixir: "~> 1.9",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :xmerl]]]
  end


  def application do
    [applications: [:logger]]
  end


  defp deps do
    [
      {:dialyxir, "~> 0.5.1", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.20.2", only: [:dev], runtime: false}
    ]
  end
end
