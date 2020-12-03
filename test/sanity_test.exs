defmodule SanityTest do
  use ExUnit.Case, async: true
  doctest Sanity

  import Mox
  setup :verify_on_exit!

  alias Sanity.{MockFinch, Request, Response}

  test "mutate" do
    assert %Request{
             body:
               "{\"mutations\":[{\"create\":{\"_type\":\"product\",\"title\":\"Test product\"}}]}",
             endpoint: :mutate,
             method: :post,
             query_params: %{"returnIds" => true}
           } ==
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
  end

  describe "query" do
    test "with params and variables" do
      assert %Request{
               body: nil,
               endpoint: :query,
               method: :get,
               query_params: %{
                 "query" => "*",
                 "$my_var" => "\"x\"",
                 "$other_var" => "2",
                 "explain" => true
               }
             } == Sanity.query("*", [my_var: "x", other_var: 2], explain: true)

      assert %Request{
               body: nil,
               endpoint: :query,
               method: :get,
               query_params: %{
                 "query" => "*[val=1]",
                 "$my_var" => "\"x\"",
                 "$other_var" => "3.3",
                 "explain" => false
               }
             } == Sanity.query("*[val=1]", %{my_var: "x", other_var: 3.3}, %{explain: false})
    end

    test "with conflicting variable and params" do
      assert %Request{
               body: nil,
               endpoint: :query,
               method: :get,
               query_params: %{
                 "query" => "*",
                 "$myvar" => "\"x\""
               }
             } == Sanity.query("*", [myvar: "x"], "$myvar": true)
    end

    test "converts query params to camelCase" do
      assert %Request{
               body: nil,
               endpoint: :query,
               method: :get,
               query_params: %{
                 "query" => "*",
                 "$my_var" => "\"x\"",
                 "someParam" => "123"
               }
             } == Sanity.query("*", [my_var: "x"], some_param: "123")
    end

    test "with invalid key type" do
      Sanity.query("*", %{"1" => "x"})

      assert_raise FunctionClauseError, fn ->
        Sanity.query("*", %{1 => "x"})
      end

      assert_raise FunctionClauseError, fn ->
        Sanity.query("*", %{}, %{2 => false})
      end
    end
  end

  test "request" do
    Mox.expect(MockFinch, :request, fn request, Sanity.Finch, [receive_timeout: 1] ->
      assert %Finch.Request{
               body: nil,
               headers: [{"authorization", "Bearer supersecret"}],
               host: "projectx.api.sanity.io",
               method: "GET",
               path: "/v1/data/query/myset",
               port: 443,
               query: "%24var_2=%22y%22&query=%2A",
               scheme: :https
             } == request

      {:ok, %Finch.Response{body: "{}", headers: [], status: 200}}
    end)

    config = [
      dataset: "myset",
      finch_mod: MockFinch,
      http_options: [receive_timeout: 1],
      project_id: "projectx",
      token: "supersecret"
    ]

    assert {:ok, %Response{body: %{}, headers: []}} ==
             Sanity.query("*", var_2: "y")
             |> Sanity.request(config)
  end
end
