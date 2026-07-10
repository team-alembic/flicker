defmodule FlickerTest do
  use ExUnit.Case, async: true

  doctest Flicker

  test "greets the world" do
    assert Flicker.hello() == :world
  end
end
