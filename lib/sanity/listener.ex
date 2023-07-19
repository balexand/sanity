defmodule Sanity.Listener do
  alias Sanity.Request

  @opts_schema [
    api_version: [
      type: :string,
      default: "v2021-10-21"
    ],
    dataset: [
      type: :string,
      doc: "Sanity dataset.",
      required: true
    ],
    variables: [
      type: :map,
      default: %{}
    ],
    token: [
      type: :string,
      doc: "Sanity auth token."
    ]
  ]

  def start_link(query, opts) do
    opts = NimbleOptions.validate!(opts, @opts_schema)

    _url =
      "https://api.sanity.io/#{opts[:api_version]}/data/listen/#{opts[:dataset]}?#{URI.encode_query(query_params)}"

    headers(opts)

    spawn_link(fn ->
      nil
    end)
  end

  defp headers(opts) do
    case Keyword.fetch(opts, :token) do
      {:ok, token} -> [{"authorization", "Bearer #{token}"}]
      :error -> []
    end
  end
end

# %Finch.Request{
#   scheme: :https,
#   host: "bk3avs8r.api.sanity.io",
#   port: 443,
#   method: "GET",
#   path: "/v2021-10-21/data/query/production",
#   headers: [
#     {"authorization",
#      "Bearer skAeidT0U9IBQHhERj4rj8EQ1AxgaFrfQTaZ8MPyJbmc5uJCNbIxQHpz4AeZppEFh3VYdYczqIaf3gY2131SPiBKMtAt0KBuJPObFnSsNT3viaJb5w3EwT6Gywyl7yWkEGFN341maqW5ztNcM6mCHOeSJvmt1K2JwGnFm9hXUyBzS2j1740L"}
#   ],
#   body: nil,
#   query: "query=_id+in+%5B%220ab67b1e-67dd-4bcb-9b22-c7a3d51649b4%22%2C+%22drafts.0ab67b1e-67dd-4bcb-9b22-c7a3d51649b4%22%5D",
#   unix_socket: nil,
#   private: %{}
# }
