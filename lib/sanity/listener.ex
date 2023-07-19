defmodule Sanity.Listener do
  defmodule Event do
    defstruct data: nil, event: nil, id: nil
  end

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
    project_id: [
      type: :string,
      doc: "Sanity project ID.",
      required: true
    ],
    query_params: [
      type: :keyword_list,
      default: []
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
    query_params = Sanity.query_to_query_params(query, opts[:variables], opts[:query_params])

    url =
      "https://#{opts[:project_id]}.api.sanity.io/#{opts[:api_version]}/data/listen/#{opts[:dataset]}?#{URI.encode_query(query_params)}"

    request = Finch.build(:get, url, headers(opts))
    pid = self()

    spawn_link(fn ->
      Finch.stream(
        request,
        Sanity.Finch,
        "",
        fn
          {:status, 200}, acc ->
            acc

          {:status, status}, _acc ->
            raise "response error status #{inspect(status)}"

          {:headers, _headers}, acc ->
            acc

          {:data, data}, acc ->
            process_data(acc <> data, pid)
        end,
        receive_timeout: 60_000
      )

      exit({:shutdown, "stream ended"})
    end)
  end

  defp process_data(data, pid) do
    case String.split(data, "\n\n", parts: 2) do
      [payload, rest] ->
        payload |> String.trim() |> process_payload(pid)
        process_data(rest, pid)

      [rest] ->
        rest
    end
  end

  defp process_payload(":", _pid), do: nil

  defp process_payload(payload, pid) do
    map =
      payload
      |> String.split("\n")
      |> Map.new(fn line ->
        [key, value] = String.split(line, ": ", parts: 2)
        {key, value}
      end)

    process_event(
      %Event{
        data: map["data"] && Jason.decode!(map["data"]),
        event: map["event"],
        id: map["id"]
      },
      pid
    )
  end

  defp process_event(%Event{event: event_name} = event, _pid)
       when event_name in ~W[channelError disconnect] do
    raise "error event #{inspect(event)}"
  end

  defp process_event(%Event{} = event, pid) do
    send(pid, event)
  end

  defp headers(opts) do
    case Keyword.fetch(opts, :token) do
      {:ok, token} -> [{"authorization", "Bearer #{token}"}]
      :error -> []
    end
  end
end
