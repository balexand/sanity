defmodule Sanity do
  alias Sanity.{Request, Response}

  # FIXME review for consistency with Javascript client-lib

  def mutate(mutations, _query_params \\ []) when is_list(mutations) do
    # FIXME support query params

    %Request{
      body: Jason.encode!(%{mutations: mutations}),
      endpoint: :mutate,
      method: :post
    }
  end

  def query(query, variables \\ %{}, query_params \\ []) do
    # FIXME don't allow query_params to include query or variable

    params =
      variables
      |> Enum.map(fn {k, v} -> {"$#{k}", Jason.encode!(v)} end)
      |> Map.new()
      |> Map.merge(Map.new(query_params))
      |> Map.merge(%{query: query})

    %Request{
      endpoint: :query,
      method: :get,
      params: params
    }
  end

  def request(%Request{body: body, method: method, params: params} = request, opts \\ []) do
    case method do
      :get ->
        url = "#{url_for(request, opts)}?#{URI.encode_query(params)}"
        Finch.build(method, url, headers(opts))

      method ->
        Finch.build(method, url_for(request, opts), headers(opts), body)
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

  defp headers(opts) do
    case Keyword.fetch(opts, :token) do
      {:ok, token} -> [{"authorization", "Bearer #{token}"}]
      :error -> []
    end
  end

  defp url_for(%Request{endpoint: :mutate}, opts) do
    "#{base_url(opts)}/v1/data/mutate/#{Keyword.fetch!(opts, :dataset)}"
  end

  defp url_for(%Request{endpoint: :query}, opts) do
    "#{base_url(opts)}/v1/data/query/#{Keyword.fetch!(opts, :dataset)}"
  end
end
