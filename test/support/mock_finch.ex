defmodule Sanity.FinchBehavior do
  @callback request(Finch.Request.t(), Finch.name(), keyword()) ::
              {:ok, Finch.Response.t()} | {:error, Mint.Types.error()}
end

Mox.defmock(Sanity.MockFinch, for: Sanity.FinchBehavior)
