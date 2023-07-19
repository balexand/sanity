defmodule Sanity do
  @moduledoc """
  Client library for Sanity CMS. See the [README](readme.html) for examples.
  """

  @behaviour Sanity.Behaviour

  require Logger
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
      default: "v2021-10-21"
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
      default: Finch,
      doc: false
    ],
    http_options: [
      type: :keyword_list,
      default: [receive_timeout: 30_000],
      doc: "Options to be passed to `Finch.request/3`."
    ],
    max_attempts: [
      type: :pos_integer,
      default: 1,
      doc:
        "Number of attempts to make before returning error. Requests receiving an HTTP status code of 4xx will not be retried."
    ],
    project_id: [
      type: :string,
      doc: "Sanity project ID."
    ],
    retry_delay: [
      type: :pos_integer,
      default: 1_000,
      doc:
        "Delay in ms to wait before retrying after an error. Applies if `max_attempts` is greater than `1`."
    ],
    token: [
      type: :string,
      doc: "Sanity auth token."
    ]
  ]

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
  Returns a list of document IDs referenced by a document or list of documents.

  ## Examples

      iex> Sanity.list_references(%{_ref: "abc", _type: "reference"})
      ["abc"]

      iex> Sanity.list_references([%{"_ref" => "one", "_type" => "reference"}, %{_ref: "two"}, %{"items" => [%{"_ref" => "three"}]}])
      ["one", "two", "three"]

      iex> Sanity.list_references([%{_ref: "abc", _type: "reference"}])
      ["abc"]

      iex> Sanity.list_references([%{a: %{_ref: "abc", _type: "reference"}, b: 1}])
      ["abc"]
  """
  def list_references(doc_or_docs) when is_list(doc_or_docs) or is_map(doc_or_docs) do
    [_list_references(doc_or_docs)] |> List.flatten() |> Enum.uniq()
  end

  defp _list_references(%{_type: "reference", _ref: ref}), do: ref
  defp _list_references(%{"_type" => "reference", "_ref" => ref}), do: ref

  # Some Sanity plugins, such as the Mux input plugin, don't include _type field in reference
  defp _list_references(%{_ref: ref} = m) when not is_map_key(m, :_type), do: ref
  defp _list_references(%{"_ref" => ref} = m) when not is_map_key(m, "_type"), do: ref

  defp _list_references(list) when is_list(list), do: Enum.map(list, &_list_references/1)
  defp _list_references(%{} = map), do: Map.values(map) |> _list_references()
  defp _list_references(_), do: []

  @spec listen(String.t(), keyword() | map(), keyword() | map()) :: Request.t()
  def listen(query, variables \\ %{}, query_params \\ []) do
    query_params =
      variables
      |> stringify_keys()
      |> Enum.map(fn {k, v} -> {"$#{k}", Jason.encode!(v)} end)
      |> Enum.into(camelize_params(query_params))
      |> Map.put("query", query)

    %Request{
      endpoint: :listen,
      method: :get,
      query_params: query_params
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
    %Request{
      endpoint: :query,
      method: :get,
      query_params: query_to_query_params(query, variables, query_params)
    }
  end

  @doc false
  def query_to_query_params(query, variables, query_params) do
    variables
    |> stringify_keys()
    |> Enum.map(fn {k, v} -> {"$#{k}", Jason.encode!(v)} end)
    |> Enum.into(camelize_params(query_params))
    |> Map.put("query", query)
  end

  @doc """
  Replaces Sanity references. The input can be a single document or list of documents. References
  can be deeply nested within the documents. Documents can have either atom or string keys.

  ## Examples

      iex> Sanity.replace_references(%{_ref: "abc", _type: "reference"}, fn "abc" -> %{_id: "abc"} end)
      %{_id: "abc"}

      iex> Sanity.replace_references(%{"_ref" => "abc", "_type" => "reference"}, fn "abc" -> %{"_id" => "abc"} end)
      %{"_id" => "abc"}

      iex> Sanity.replace_references(%{_ref: "abc"}, fn "abc" -> %{_id: "abc"} end)
      %{_id: "abc"}

      iex> Sanity.replace_references(%{"_ref" => "abc"}, fn "abc" -> %{"_id" => "abc"} end)
      %{"_id" => "abc"}

      iex> Sanity.replace_references([%{_ref: "abc", _type: "reference"}], fn _ -> %{_id: "abc"} end)
      [%{_id: "abc"}]

      iex> Sanity.replace_references([%{a: %{_ref: "abc", _type: "reference"}, b: 1}], fn _ -> %{_id: "abc"} end)
      [%{a: %{_id: "abc"}, b: 1}]
  """
  @spec replace_references(list() | map(), fun()) :: list() | map()
  def replace_references(doc_or_docs, func)
      when (is_list(doc_or_docs) or is_map(doc_or_docs)) and is_function(func) do
    _replace_references(doc_or_docs, func)
  end

  defp _replace_references(list, func) when is_list(list) do
    Enum.map(list, &_replace_references(&1, func))
  end

  defp _replace_references(%{_type: "reference", _ref: ref}, func), do: func.(ref)
  defp _replace_references(%{"_type" => "reference", "_ref" => ref}, func), do: func.(ref)

  # Some Sanity plugins, such as the Mux input plugin, don't include _type field in reference
  defp _replace_references(%{_ref: ref} = m, func) when not is_map_key(m, :_type), do: func.(ref)

  defp _replace_references(%{"_ref" => ref} = m, func) when not is_map_key(m, "_type"),
    do: func.(ref)

  defp _replace_references(%{} = map, func) do
    Map.new(map, fn {k, v} -> {k, _replace_references(v, func)} end)
  end

  defp _replace_references(any, _func), do: any

  @doc """
  Returns the result from a `Sanity.Response` struct.

  ## Examples

      iex> Sanity.result!(%Sanity.Response{body: %{"result" => []}})
      []

      iex> Sanity.result!(%Sanity.Response{body: %{}, status: 200})
      ** (Sanity.Error) %Sanity.Response{body: %{}, headers: nil, status: 200}
  """
  @spec result!(Response.t()) :: any()
  def result!(%Response{body: %{"result" => result}}), do: result
  def result!(%Response{} = response), do: raise(%Sanity.Error{source: response})

  @doc """
  Submits a request to the Sanity API. Returns `{:ok, response}` upon success or `{:error,
  response}` if a non-exceptional (4xx) error occurs. A `Sanity.Error` will be raised if an
  exceptional error such as a 5xx response code, a network timeout, or a response containing
  non-JSON content occurs.

  ## Options

  #{NimbleOptions.docs(@request_options_schema)}
  """
  @impl true
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

    result =
      Finch.build(method, url, headers(opts) ++ headers, body)
      |> finch_mod.request(Sanity.Finch, http_options)

    case {opts[:max_attempts], result} do
      {_, {:ok, %Finch.Response{body: body, headers: headers, status: status}}}
      when status in 200..299 ->
        {:ok, %Response{body: Jason.decode!(body), headers: headers, status: status}}

      {_, {:ok, %Finch.Response{body: body, headers: headers, status: status} = resp}}
      when status in 400..499 ->
        if json_resp?(headers) do
          {:error, %Response{body: Jason.decode!(body), headers: headers, status: status}}
        else
          raise %Sanity.Error{source: resp}
        end

      {max_attempts, {_, error_or_response}} when max_attempts > 1 ->
        Logger.warning(
          "retrying failed request in #{opts[:retry_delay]}ms: #{inspect(error_or_response)}"
        )

        :timer.sleep(opts[:retry_delay])

        opts =
          opts
          |> Keyword.update!(:max_attempts, &(&1 - 1))
          |> Keyword.update!(:retry_delay, &(&1 * 2))

        request(request, opts)

      {_, {_, error_or_response}} ->
        raise %Sanity.Error{source: error_or_response}
    end
  end

  defp json_resp?(headers) do
    Enum.any?(headers, fn
      {"content-type", value} -> String.contains?(value, "application/json")
      {_name, _value} -> false
    end)
  end

  @doc """
  Like `request/2`, but raises a `Sanity.Error` instead of returning and error tuple.

  See `request/2` for supported options.
  """
  @impl true
  @spec request!(Request.t(), keyword()) :: Response.t()
  def request!(request, opts \\ []) do
    case request(request, opts) do
      {:ok, %Response{} = response} -> response
      {:error, %Response{} = response} -> raise %Sanity.Error{source: response}
    end
  end

  @stream_options_schema [
    batch_size: [
      type: :pos_integer,
      default: 1_000,
      doc:
        ~S'Number of results to fetch per request. The Sanity docs say: "In the general case, we recommend a batch size of no more than 5,000. If your documents are very large, a smaller batch size is better."'
    ],
    drafts: [
      type: {:in, [:exclude, :include, :only]},
      default: :exclude,
      doc:
        "Use `:exclude` to exclude drafts, `:include` to include drafts along with published docs, or `:only` to fetch drafts and not published documents."
    ],
    projection: [
      type: :string,
      default: "{ ... }",
      doc: "GROQ projection. Must include the `_id` field."
    ],
    query: [
      type: :string,
      doc: ~S'Query string, like `_type == "page"`. By default, all documents will be selected.'
    ],
    request_module: [
      type: :atom,
      default: __MODULE__,
      doc: false
    ],
    request_opts: [
      type: :keyword_list,
      required: true,
      doc:
        "Options to be passed to `request/2`. If `max_attempts` is omitted then it will default to `3`."
    ],
    variables: [
      type: {:map, {:or, [:atom, :string]}, :any},
      default: %{},
      doc: "Map of variables to be used with `query`."
    ]
  ]

  @doc """
  Returns a lazy `Stream` of results for the given query. The implementation is efficient and
  suitable for iterating over very large datasets. It is based on the [Paginating with
  GROQ](https://www.sanity.io/docs/paginating-with-groq) article from the Sanity docs.

  Failed attempts to fetch a batch will be retried by default. If the max attempts are exceeded
  then an exception will be raised as descrbied in `request!/2`.

  The current implementation always sorts by ascending `_id`. Support for sorting by other fields
  may be supported in the future.

  ## Options

  #{NimbleOptions.docs(@stream_options_schema)}
  """
  @impl true
  @spec stream(Keyword.t()) :: Enumerable.t()
  def stream(opts) do
    opts =
      opts
      |> NimbleOptions.validate!(@stream_options_schema)
      |> Keyword.update!(:request_opts, &Keyword.put_new(&1, :max_attempts, 3))

    case Map.take(opts[:variables], [:pagination_last_id, "pagination_last_id"]) |> Map.keys() do
      [] -> nil
      keys -> raise ArgumentError, "variable names not permitted: #{inspect(keys)}"
    end

    Stream.unfold(:first_page, fn
      :done ->
        nil

      :first_page ->
        stream_page(opts, nil)

      last_id ->
        opts
        |> Keyword.update!(:variables, &Map.put(&1, :pagination_last_id, last_id))
        |> stream_page("_id > $pagination_last_id")
    end)
    |> Stream.flat_map(& &1)
  end

  defp stream_page(opts, page_query) do
    query =
      [opts[:query], drafts_query(opts[:drafts]), page_query]
      |> Enum.filter(& &1)
      |> Enum.map(&"(#{&1})")
      |> Enum.join(" && ")

    results =
      "*[#{query}] | order(_id) [0..#{opts[:batch_size] - 1}] #{opts[:projection]}"
      |> query(opts[:variables])
      |> opts[:request_module].request!(opts[:request_opts])
      |> result!()

    if length(results) < opts[:batch_size] do
      {results, :done}
    else
      {results, results |> List.last() |> Map.fetch!("_id")}
    end
  end

  defp drafts_query(:exclude), do: "!(_id in path('drafts.**'))"
  defp drafts_query(:include), do: nil
  defp drafts_query(:only), do: "_id in path('drafts.**')"

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
