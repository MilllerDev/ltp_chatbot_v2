[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["apps/*"],
  inputs: [
    "mix.exs",
    "config/*.exs",
    "apps/*/{mix.exs,lib,test}/**/*.{ex,exs}"
  ]
]
