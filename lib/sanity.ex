defmodule Sanity do
  @moduledoc """
  Client library for Sanity CMS. See the [README](readme.html) for examples.
  """

  alias Sanity.{Request, Response}

  @asset_options_schema [
    asset_type: [
      default: :image,
      type: {:in, [:image, :file]}
    ],
    content_type: [
      type: :string
    ]
  ]

  @request_options_schema [
    api_version: [
      type: :string,
      default: "v2021-03-25"
    ],
    cdn: [
      type: :boolean,
      default: false,
      doc:
        "Should the CDN be used? See the [Sanity docs](https://www.sanity.io/docs/api-cdn) for details."
    ],
    dataset: [
      type: :string,
      doc: "Sanity dataset."
    ],
    finch_mod: [
      type: :atom,
      doc: false,
      default: Finch
    ],
    http_options: [
      type: :keyword_list,
      doc: "Options to be passed to `Finch.request/3`.",
      default: []
    ],
    project_id: [
      type: :string,
      doc: "Sanity project ID."
    ],
    token: [
      type: :string,
      doc: "Sanity auth token."
    ]
  ]

  @doc """
  Convenience function for fetching a single document by ID. See `doc/1`.

  See `request/2` for supported options.
  """
  @spec get_document(String.t(), keyword()) :: map() | nil
  def get_document(document_id, opts) do
    doc(document_id)
    |> request!(opts)
    |> case do
      %Response{body: %{"documents" => []}} -> nil
      %Response{body: %{"documents" => [doc]}} -> doc
    end
  end

  @doc """
  Convenience function for fetching a list of documents by ID. See `doc/1`.

  The order/position of documents is preserved based on the original list of IDs. If any documents
  cannot be found then the returned list will contain `nil` for that document.

  See `request/2` for supported options.
  """
  @spec get_documents([String.t()], keyword()) :: [map()]
  def get_documents(document_ids, opts) do
    %Response{body: %{"documents" => documents}} =
      document_ids
      |> Enum.join(",")
      |> doc()
      |> request!(opts)

    docs_by_id =
      documents
      |> Enum.map(fn %{"_id" => id} = doc -> {id, doc} end)
      |> Map.new()

    Enum.map(document_ids, &docs_by_id[&1])
  end

  @doc """
  Generates a request for the [Doc endpoint](https://www.sanity.io/docs/http-doc).

  The Sanity docs suggest using this endpoint sparingly because it is "less scalable/performant"
  than using `query/3`. See `get_document/2` and `get_documents/2` for a more convenient
  interface.
  """
  @spec doc(String.t()) :: Request.t()
  def doc(document_id) when is_binary(document_id) do
    %Request{
      endpoint: :doc,
      method: :get,
      path_params: %{document_id: document_id}
    }
  end

  @doc """
  Generates a request for the [Mutate](https://www.sanity.io/docs/http-mutations) endpoint.

  ## Example

      Sanity.mutate(
        [
          %{
            create: %{
              _type: "product",
              title: "Test product"
            }
          }
        ],
        return_ids: true
      )
      |> Sanity.request(config)
  """
  @spec mutate([map], keyword() | map()) :: Request.t()
  def mutate(mutations, query_params \\ []) when is_list(mutations) do
    %Request{
      body: Jason.encode!(%{mutations: mutations}),
      endpoint: :mutate,
      method: :post,
      query_params: camelize_params(query_params)
    }
  end

  @doc """
  Generates a request to the [Query](https://www.sanity.io/docs/http-query) endpoint. Requests to
  this endpoint may be authenticated or unauthenticated. Unauthenticated requests to a dataset
  with private visibility will succeed but will not return any documents.
  """
  @spec query(String.t(), keyword() | map(), keyword() | map()) :: Request.t()
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
  Submits a request to the Sanity API. Returns `{:ok, response}` upon success or `{:error,
  response}` if a non-exceptional (4xx) error occurs. A `Sanity.Error` will be raised if an
  exceptional error, such as a 5xx response code or a network timeout, occurs.

  ## Options

  #{NimbleOptions.docs(@request_options_schema)}
  """
  @spec request(Request.t(), keyword()) :: {:ok, Response.t()} | {:error, Response.t()}
  def request(
        %Request{body: body, headers: headers, method: method, query_params: query_params} =
          request,
        opts \\ []
      ) do
    opts = NimbleOptions.validate!(opts, @request_options_schema)

    finch_mod = Keyword.fetch!(opts, :finch_mod)
    http_options = Keyword.fetch!(opts, :http_options)

    url = "#{url_for(request, opts)}?#{URI.encode_query(query_params)}"

    Finch.build(method, url, headers(opts) ++ headers, body)
    |> finch_mod.request(Sanity.Finch, http_options)
    |> case do
      {:ok, %Finch.Response{body: body, headers: headers, status: status}}
      when status in 200..299 ->
        {:ok, %Response{body: Jason.decode!(body), headers: headers}}

      {:ok, %Finch.Response{body: body, headers: headers, status: status}}
      when status in 400..499 ->
        {:error, %Response{body: Jason.decode!(body), headers: headers}}

      {_, error_or_response} ->
        raise %Sanity.Error{source: error_or_response}
    end
  end

  @doc """
  Like `request/2`, but raises a `Sanity.Error` instead of returning and error tuple.

  See `request/2` for supported options.
  """
  @spec request!(Request.t(), keyword()) :: Response.t()
  def request!(request, opts \\ []) do
    case request(request, opts) do
      {:ok, %Response{} = response} -> response
      {:error, %Response{} = response} -> raise %Sanity.Error{source: response}
    end
  end

  # FIXME typespec and doc
  def upload_asset(body, opts \\ [], query_params \\ []) do
    opts = NimbleOptions.validate!(opts, @asset_options_schema)

    headers =
      case opts[:content_type] do
        nil -> []
        content_type -> [{"content-type", content_type}]
      end

    %Request{
      body: body,
      endpoint: :assets,
      headers: headers,
      method: :post,
      query_params: camelize_params(query_params),
      path_params: %{asset_type: opts[:asset_type]}
    }
  end

  defp base_url(opts) do
    domain =
      if Keyword.get(opts, :cdn) do
        "apicdn.sanity.io"
      else
        "api.sanity.io"
      end

    "https://#{request_opt!(opts, :project_id)}.#{domain}"
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

  defp url_for(%Request{endpoint: :assets, path_params: %{asset_type: asset_type}}, opts) do
    api_version = request_opt!(opts, :api_version)
    dataset = request_opt!(opts, :dataset)

    "#{base_url(opts)}/#{api_version}/assets/#{asset_type}s/#{dataset}"
  end

  defp url_for(%Request{endpoint: :doc, path_params: %{document_id: document_id}}, opts) do
    api_version = request_opt!(opts, :api_version)
    dataset = request_opt!(opts, :dataset)

    "#{base_url(opts)}/#{api_version}/data/doc/#{dataset}/#{document_id}"
  end

  defp url_for(%Request{endpoint: :mutate}, opts) do
    api_version = request_opt!(opts, :api_version)
    dataset = request_opt!(opts, :dataset)

    "#{base_url(opts)}/#{api_version}/data/mutate/#{dataset}"
  end

  defp url_for(%Request{endpoint: :query}, opts) do
    api_version = request_opt!(opts, :api_version)
    dataset = request_opt!(opts, :dataset)

    "#{base_url(opts)}/#{api_version}/data/query/#{dataset}"
  end

  defp request_opt!(opts, key) do
    schema = Keyword.update!(@request_options_schema, key, &Keyword.put(&1, :required, true))
    NimbleOptions.validate!(opts, schema)

    Keyword.fetch!(opts, key)
  end
end
