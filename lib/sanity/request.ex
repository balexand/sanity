defmodule Sanity.Request do
  @type t :: %Sanity.Request{}

  defstruct body: nil,
            endpoint: nil,
            method: nil,
            path_params: nil,
            query_params: %{}
end
