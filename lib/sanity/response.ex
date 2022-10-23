defmodule Sanity.Response do
  @type t :: %Sanity.Response{}

  defstruct [:body, :headers, :status]
end
