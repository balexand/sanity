defmodule Sanity.MutateIntegrationTest do
  use ExUnit.Case, async: true

  alias Sanity.Response

  @moduletag :integration

  setup_all do
    project_id =
      System.get_env("ELIXIR_SANITY_TEST_PROJECT_ID") ||
        raise "ELIXIR_SANITY_TEST_PROJECT_ID env var must be set"

    token =
      System.get_env("ELIXIR_SANITY_TEST_TOKEN") ||
        raise "ELIXIR_SANITY_TEST_TOKEN env var must be set"

    config = [dataset: "test", project_id: project_id, token: token]

    Sanity.mutate([
      %{delete: %{query: ~S'*[
          !(string::startsWith(_type, "system.")) &&
          dateTime(now()) - dateTime(_createdAt) > 60
        ]'}}
    ])
    |> Sanity.request!(config)

    %{config: config}
  end

  test "doc", %{config: config} do
    {:ok, %Response{body: %{"results" => [%{"id" => id}]}}} =
      Sanity.mutate(
        [
          %{create: %{_type: "product", title: "product x"}}
        ],
        return_ids: true
      )
      |> Sanity.request(config)

    assert {:ok,
            %Response{
              body: %{"documents" => [%{"title" => "product x"}]},
              headers: %{"content-type" => ["application/json; charset=utf-8"]}
            }} =
             Sanity.doc(id) |> Sanity.request(config)
  end

  test "mutate", %{config: config} do
    assert {:ok,
            %Response{
              body: %{"results" => [%{"id" => id, "operation" => "create"}], "transactionId" => _}
            }} =
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

    assert(
      {:ok, %Response{body: %{"results" => [%{"document" => %{"title" => "Updated title"}}]}}} =
        Sanity.mutate(
          [
            %{
              patch: %{
                id: id,
                set: %{
                  title: "Updated title"
                }
              }
            }
          ],
          return_documents: true
        )
        |> Sanity.request(config)
    )

    assert {:error, %Response{body: %{"error" => %{"description" => _}}, status: 409}} =
             Sanity.mutate([
               %{
                 patch: %{
                   id: id,
                   ifRevisionID: "xo35MqpmFOvWQMRCPkokuZ",
                   set: %{
                     title: "Updated title 2"
                   }
                 }
               }
             ])
             |> Sanity.request(config)
  end

  test "query", %{config: config} do
    assert {:ok, %Response{body: %{"query" => "{\"hello\": \"world\"}", "result" => result}}} =
             Sanity.query(~S<{"hello": "world"}>)
             |> Sanity.request(config)

    assert result == %{"hello" => "world"}

    assert {:ok, %Response{body: %{"query" => "{\"hello\": $my_var}", "result" => result}}} =
             Sanity.query(~S<{"hello": $my_var}>, %{my_var: "x"})
             |> Sanity.request(config)

    assert result == %{"hello" => "x"}

    assert {:ok, %Response{body: %{"explain" => <<_::binary>>}}} =
             Sanity.query(~S<{"hello": "world"}>, %{}, explain: true)
             |> Sanity.request(config)

    assert {:error,
            %Response{
              body: %{"error" => %{"description" => "param $my_var referenced, but not provided"}},
              status: 400
            }} =
             Sanity.query(~S<{"hello": $my_var}>)
             |> Sanity.request(config)

    # with CDN
    assert {:ok, %Response{body: %{"query" => "{\"hello\": \"world\"}", "result" => _}}} =
             Sanity.query(~S<{"hello": "world"}>)
             |> Sanity.request(Keyword.put(config, :cdn, true))
  end

  describe "stream" do
    test "with multiple batches", %{config: config} do
      type = "streamItem#{:rand.uniform(1_000_000)}"

      Sanity.mutate(Enum.map(1..5, &%{create: %{_type: type, title: "item #{&1}"}}))
      |> Sanity.request!(config)

      Sanity.mutate([
        %{create: %{_id: "drafts.a-#{:rand.uniform(1_000_000)}", _type: type, title: "my draft"}}
      ])
      |> Sanity.request!(config)

      assert [
               %{"title" => "item 1"},
               %{"title" => "item 2"},
               %{"title" => "item 3"},
               %{"title" => "item 4"},
               %{"title" => "item 5"}
             ] =
               Sanity.stream(query: "_type == '#{type}'", batch_size: 2, request_opts: config)
               |> Enum.to_list()
               |> Enum.sort_by(& &1["title"])
    end

    test "with perspectives", %{config: config} do
      type = "streamItem#{:rand.uniform(1_000_000)}"
      id = "my-id-#{:rand.uniform(1_000_000)}"

      Sanity.mutate([
        %{create: %{_id: id, _type: type, title: "published item"}},
        %{create: %{_id: "drafts.#{id}", _type: type, title: "draft item"}}
      ])
      |> Sanity.request!(config)

      # Published (default)
      assert [%{"_id" => ^id, "title" => "published item"}] =
               Sanity.stream(
                 query: "_type == '#{type}'",
                 request_opts: config
               )
               |> Enum.to_list()

      # Preview drafts
      assert [%{"_id" => ^id, "title" => "draft item"}] =
               Sanity.stream(
                 query: "_type == '#{type}'",
                 perspective: "previewDrafts",
                 request_opts: config
               )
               |> Enum.to_list()

      # Raw
      assert [
               %{"_id" => "drafts." <> ^id, "title" => "draft item"},
               %{"_id" => ^id, "title" => "published item"}
             ] =
               Sanity.stream(
                 query: "_type == '#{type}'",
                 perspective: "raw",
                 request_opts: config
               )
               |> Enum.to_list()
    end
  end

  describe "upload_asset" do
    test "binary jpg asset", %{config: config} do
      binary = File.read!("test/fixtures/danielle-stein-10OL1q7oX6c-unsplash.jpg")

      assert %Sanity.Response{
               body: %{
                 "document" => %{
                   "_type" => "sanity.imageAsset",
                   "metadata" => %{
                     "dimensions" => %{
                       "_type" => "sanity.imageDimensions",
                       "height" => 960,
                       "width" => 640
                     }
                   },
                   "mimeType" => "image/jpeg",
                   "sha1hash" => "41de39c94c974305bdda7d901cfca3102a8e6e77",
                   "size" => 169_633
                 }
               }
             } =
               Sanity.upload_asset(binary)
               |> Sanity.request!(config)
    end

    test "stream jpg asset", %{config: config} do
      stream =
        File.stream!(
          "test/fixtures/danielle-stein-10OL1q7oX6c-unsplash.jpg",
          [:raw, :read_ahead, :binary],
          2048
        )

      assert %Sanity.Response{
               body: %{
                 "document" => %{
                   "_type" => "sanity.imageAsset",
                   "mimeType" => "image/jpeg",
                   "sha1hash" => "41de39c94c974305bdda7d901cfca3102a8e6e77",
                   "size" => 169_633
                 }
               }
             } =
               Sanity.upload_asset(stream)
               |> Sanity.request!(config)
    end
  end

  test "timeout error", %{config: config} do
    config = Keyword.put(config, :http_options, receive_timeout: 0, retry: false)

    assert_raise Sanity.Error, "%Mint.TransportError{reason: :timeout}", fn ->
      Sanity.query(~S<{"hello": "world"}>)
      |> Sanity.request(config)
    end
  end
end
