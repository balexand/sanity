defmodule Sanity.Behaviour do
  @moduledoc """
  Behaviour implemented by the `Sanity` module. This behaviour includes all functions that make
  requests to the Sanity API. Pure functions from the `Sanity` module are not included. This
  behaviour is useful for creating mocks using the `Mox` library.
  """

  alias Sanity.{Request, Response}

  @callback request(Request.t(), keyword()) :: {:ok, Response.t()} | {:error, Response.t()}
  @callback request!(Request.t(), keyword()) :: Response.t()
  @callback stream(Keyword.t()) :: Enumerable.t()
end
