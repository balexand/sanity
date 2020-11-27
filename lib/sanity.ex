defmodule Sanity do
  alias Sanity.{Request, Response}

  # FIXME review for consistency with Javascript client-lib

  def mutate(mutations, query_params \\ []) when is_list(mutations) do
    %Request{
      body: Jason.encode!(%{mutations: mutations}),
      endpoint: :mutate,
      method: :post,
      query_params: query_params
    }
  end

  def query(query, variables \\ %{}, query_params \\ []) do
    # FIXME don't allow query_params to include query or variable

    query_params =
      variables
      |> Enum.map(fn {k, v} -> {"$#{k}", Jason.encode!(v)} end)
      |> Map.new()
      |> Map.merge(Map.new(query_params))
      |> Map.merge(%{query: query})

    %Request{
      endpoint: :query,
      method: :get,
      query_params: query_params
    }
  end

  def request(
        %Request{body: body, method: method, query_params: query_params} = request,
        opts \\ []
      ) do
    # TODO support client opts, like :receive_timeout
    url = "#{url_for(request, opts)}?#{URI.encode_query(query_params)}"

    Finch.build(method, url, headers(opts), body)
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
