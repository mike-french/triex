defmodule Triex.MixProject do
  use Mix.Project

  def project do
    [
      app: :triex,
      name: "Triex",
      version: "0.1.0",
      elixir: "~> 1.15",
      erlc_options: [:verbose, :report_errors, :report_warnings, :export_all],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      test_pattern: "*_test.exs",
      dialyzer: [flags: [:no_improper_lists]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # :logger
      extra_applications: []
    ]
  end

  def docs do
    [
      main: "Triex",
      output: "doc/api",
      extras: ["README.md"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # runtime code dependencies ------------------
      # {:exa, git: "https://github.com/mike-french/exa.git", tag: "0.1.0"}
      # {:exa, path: "../exa"},

      # building, documenting and testing ----------

      # typechecking
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},

      # documentation
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},

      # benchmarking
      {:benchee, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
