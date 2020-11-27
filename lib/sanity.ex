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

  def request(%Request{method: method, params: params} = request, opts \\ []) do
    case method do
      :get ->
        url = "#{url_for(request, opts)}?#{URI.encode_query(params)}"
        Finch.build(method, url)
    end
    |> Finch.request(Sanity.Finch)
    |> case do
      {:ok, %Finch.Response{body: body, headers: headers, status: status}}
      when status in 200..299 ->
        {:ok, %Response{body: Jason.decode!(body), headers: headers}}

      {:ok, %Finch.Response{body: body, headers: headers, status: status}}
      when status in 400..499 ->
        {:error, %Response{body: Jason.decode!(body), headers: headers}}
    end

    # TODO raise a more useful exception than MatchError on http error
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
