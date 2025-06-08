# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,priv}/**/*.{ex,exs}"],
  import_deps: [:ash_postgres, :ash, :reactor, :oban],
  plugins: [Spark.Formatter]
]
