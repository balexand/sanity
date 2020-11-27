defmodule Sanity do
  alias Sanity.{Request, Response}

  # FIXME review for consistency with Javascript client-lib

  def query(query, variables \\ %{}, params \\ []) do
    # FIXME don't allow params to include query or variable

    params =
      variables
      |> Enum.map(fn {k, v} -> {"$#{k}", Jason.encode!(v)} end)
      |> Map.new()
      |> Map.merge(Map.new(params))
      |> Map.merge(%{query: query})

    %Request{
      endpoint: :query,
      method: :get,
      params: params
    }
  end

  def request!(%Request{method: method, params: params} = request, opts \\ []) do
    # TODO raise a more useful exception than MatchError
    {:ok, %Finch.Response{body: body, headers: headers}} =
      case method do
        :get ->
          url = "#{url_for(request, opts)}?#{URI.encode_query(params)}"
          Finch.build(method, url)
      end
      |> Finch.request(Sanity.Finch)

    %Response{body: Jason.decode!(body), headers: headers}
  end

  defp base_url(opts) do
    # FIXME support cdn
    project_id = Keyword.fetch!(opts, :project_id)
    "https://#{project_id}.api.sanity.io"
  end

  defp url_for(%Request{endpoint: :query}, opts) do
    "#{base_url(opts)}/v1/data/query/#{Keyword.fetch!(opts, :dataset)}"
  end
end
