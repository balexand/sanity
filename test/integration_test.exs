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
      %{delete: %{query: ~S<*[_type in ["sanity.imageAsset", "product"]]>}}
    ])
    |> Sanity.request(config)

    %{config: config}
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
               returnIds: true
             )
             |> Sanity.request(config)

    assert {:ok,
            %Response{body: %{"results" => [%{"document" => %{"title" => "Updated title"}}]}}} =
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
               # FIXME underscore case
               returnDocuments: true
             )
             |> Sanity.request(config)

    assert {:error, %Response{body: %{"error" => %{"description" => description}}}} =
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

    assert description =~ "has unexpected revision ID"
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
              body: %{"error" => %{"description" => "Param $my_var referenced, but not provided"}}
            }} =
             Sanity.query(~S<{"hello": $my_var}>)
             |> Sanity.request(config)
  end
end
