unless System.get_env("CI") do
  ExUnit.configure(exclude: [integration: true])
end

ExUnit.start()
