defmodule SanityTest do
  use ExUnit.Case
  doctest Sanity

  test "greets the world" do
    assert Sanity.hello() == :world
  end
end
