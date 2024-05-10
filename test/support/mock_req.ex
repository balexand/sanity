defmodule Sanity.ReqBehavior do
  @callback request(keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
end

Mox.defmock(Sanity.MockReq, for: Sanity.ReqBehavior)
