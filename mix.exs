defmodule Sanity.MixProject do
  use Mix.Project

  def project do
    [
      app: :sanity,
      version: "0.1.0",
      elixir: "~> 1.8",
      description: "Client library for Sanity CMS.",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/balexand/sanity"}
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Sanity.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finch, "~> 0.5"},
      {:jason, "~> 1.2"}
    ]
  end
end
