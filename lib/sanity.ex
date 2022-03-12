defmodule Sanity do
  @moduledoc """
  Client library for Sanity CMS. See the [README](readme.html) for examples.
  """

  alias Sanity.{Request, Response}

  @asset_options_schema [
    asset_type: [
      default: :image,
      type: {:in, [:image, :file]},
      doc: "Either `:image` or `:file`."
    ],
    content_type: [
      type: :string,
      doc: "Optional `content-type` header. It appears that Sanity is able to infer image types."
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
  Deeply traverses nested maps and lists and converts string keys to atoms in underscore_case.

  ## Examples

    iex> Sanity.atomize_and_underscore(%{"_id" => "123", "myField" => [%{"aB" => "aB"}]})
    %{_id: "123", my_field: [%{a_b: "aB"}]}

    iex> Sanity.atomize_and_underscore([%{"abcDef" => 1}])
    [%{abc_def: 1}]
  """
  @spec atomize_and_underscore(any()) :: any()
  def atomize_and_underscore(%{} = map) do
    map
    |> Enum.map(fn
      {k, v} when is_binary(k) ->
        {k |> Macro.underscore() |> String.to_atom(), atomize_and_underscore(v)}

      {k, v} ->
        {k, atomize_and_underscore(v)}
    end)
    |> Map.new()
  end

  def atomize_and_underscore(list) when is_list(list) do
    Enum.map(list, &atomize_and_underscore/1)
  end

  def atomize_and_underscore(v), do: v

  @doc """
  Generates a request for the [Doc endpoint](https://www.sanity.io/docs/http-doc).

  The Sanity docs suggest using this endpoint sparingly because it is "less scalable/performant"
  than using `query/3`.
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

  ## Examples

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
  Returns the result from a `Sanity.Response` struct.

  ## Examples

    iex> Sanity.result!(%Sanity.Response{body: %{"result" => []}})
    []

    iex> Sanity.result!(%Sanity.Response{body: %{}})
    ** (Sanity.Error) %Sanity.Response{body: %{}, headers: nil}
  """
  @spec result!(Response.t()) :: any()
  def result!(%Response{body: %{"result" => result}}), do: result
  def result!(%Response{} = response), do: raise(%Sanity.Error{source: response})

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

  @doc """
  Generates a request for the [asset endpoint](https://www.sanity.io/docs/http-api-assets).

  ## Options

  #{NimbleOptions.docs(@asset_options_schema)}

  ## Query params

  Sanity doesn't document the query params very well at this time, but the [Sanity Javascript
  client](https://github.com/sanity-io/sanity/blob/next/packages/%40sanity/client/src/assets/assetsClient.js)
  lists several possible query params:

    * `label` - Label
    * `title` - Title
    * `description` - Description
    * `filename` - Original filename
    * `meta` - ???
    * `creditLine` - The credit to person(s) and/or organization(s) required by the supplier of
      the image to be used when published
  """
  @spec upload_asset(iodata(), keyword() | map(), keyword() | map()) :: Request.t()
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
