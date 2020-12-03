defmodule Sanity.Response do
  @type t :: %Sanity.Response{}

  defstruct [:body, :headers]
end
