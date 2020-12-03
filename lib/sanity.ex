defmodule Sanity do
  alias Sanity.{Request, Response}

  # FIXME review for consistency with Javascript client-lib

  def mutate(mutations, query_params \\ []) when is_list(mutations) do
    %Request{
      body: Jason.encode!(%{mutations: mutations}),
      endpoint: :mutate,
      method: :post,
      query_params: camelize_params(query_params)
    }
  end

  def query(query, variables \\ %{}, query_params \\ []) do
    query_params =
      variables
      |> stringify_keys()
      |> Enum.map(fn {k, v} -> {"$#{k}", Jason.encode!(v)} end)
      |> Enum.into(camelize_params(query_params))
      |> Map.put("query", query)

    %Request{
      endpoint: :query,
      method: :get,
      query_params: query_params
    }
  end

  @doc """
  Sends a request and returns a `Sanity.Response` struct.

  ## Options

    * `dataset` - Sanity dataset
    * `http_options` - Options to be passed to `Finch.request/3`
    * `project_id` - Sanity project ID
  """
  @spec request(Request.t(), keyword()) :: {:ok, Response.t()} | {:error, Response.t()}
  def request(
        %Request{body: body, method: method, query_params: query_params} = request,
        opts \\ []
      ) do
    finch_mod = Keyword.get(opts, :finch_mod, Finch)
    http_options = Keyword.get(opts, :http_options, [])

    url = "#{url_for(request, opts)}?#{URI.encode_query(query_params)}"

    Finch.build(method, url, headers(opts), body)
    |> finch_mod.request(Sanity.Finch, http_options)
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

  defp camelize_params(pairs) do
    pairs
    |> stringify_keys()
    |> Enum.map(fn {k, v} ->
      {first, rest} = k |> Macro.camelize() |> String.split_at(1)
      {String.downcase(first) <> rest, v}
    end)
    |> Map.new()
  end

  defp stringify_keys(pairs) do
    pairs
    |> Enum.map(fn
      {k, v} when is_binary(k) -> {k, v}
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
    end)
    |> Map.new()
  end

  defp url_for(%Request{endpoint: :mutate}, opts) do
    "#{base_url(opts)}/v1/data/mutate/#{Keyword.fetch!(opts, :dataset)}"
  end

  defp url_for(%Request{endpoint: :query}, opts) do
    "#{base_url(opts)}/v1/data/query/#{Keyword.fetch!(opts, :dataset)}"
  end
end
