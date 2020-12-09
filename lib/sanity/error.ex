defmodule Sanity.Error do
  @moduledoc """
  Error that may occur while making a request to the Sanity API. The `source` field will be one of
  the following:

    * `%Finch.Response{}` - If response with an unsupported HTTP status (like 5xx) is received.
    * `%Mint.TransportError{}` - If a network error such as a timeout occurred.
    * `%Sanity.Response{}` - If a 4xx response is received during a call to `Sanity.request!/2`.
  """

  defexception [:source]

  @impl true
  def message(%Sanity.Error{source: source}), do: inspect(source)
end
