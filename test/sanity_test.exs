defmodule SanityTest do
  use ExUnit.Case, async: true
  doctest Sanity

  import Mox
  setup :verify_on_exit!

  alias Sanity.{MockFinch, MockSanity, Request, Response}
  alias NimbleOptions.ValidationError

  @request_config [
    dataset: "myset",
    finch_mod: MockFinch,
    http_options: [receive_timeout: 1],
    project_id: "projectx",
    token: "supersecret"
  ]

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

  describe "request" do
    test "with query" do
      Mox.expect(MockFinch, :request, fn request, Sanity.Finch, [receive_timeout: 1] ->
        assert %Finch.Request{
                 body: nil,
                 headers: [{"authorization", "Bearer supersecret"}],
                 host: "projectx.api.sanity.io",
                 method: "GET",
                 path: "/v2021-10-21/data/query/myset",
                 port: 443,
                 query: "%24var_2=%22y%22&query=%2A",
                 scheme: :https
               } == request

        {:ok, %Finch.Response{body: "{}", headers: [], status: 200}}
      end)

      assert {:ok, %Response{body: %{}, headers: [], status: 200}} ==
               Sanity.query("*", var_2: "y")
               |> Sanity.request(@request_config)
    end

    test "with CDN URL" do
      Mox.expect(MockFinch, :request, fn %Finch.Request{host: "projectx.apicdn.sanity.io"},
                                         Sanity.Finch,
                                         _ ->
        {:ok, %Finch.Response{body: "{}", headers: [], status: 200}}
      end)

      assert {:ok, %Response{body: %{}, headers: [], status: 200}} ==
               Sanity.query("*")
               |> Sanity.request(Keyword.put(@request_config, :cdn, true))
    end

    test "options validations" do
      query = Sanity.query("*")

      assert_raise ValidationError, "expected :dataset to be a string, got: :ok", fn ->
        Sanity.request(query, dataset: :ok)
      end

      assert_raise ValidationError, "expected :http_options to be a keyword list, got: %{}", fn ->
        Sanity.request(query, http_options: %{})
      end

      assert_raise ValidationError, "expected :project_id to be a string, got: 1", fn ->
        Sanity.request(query, project_id: 1)
      end

      assert_raise ValidationError, ~R{required option :dataset not found}, fn ->
        Sanity.request(query, Keyword.delete(@request_config, :dataset))
      end
    end

    test "5xx response" do
      Mox.expect(MockFinch, :request, fn %Finch.Request{}, Sanity.Finch, _ ->
        {:ok, %Finch.Response{body: "fail!", headers: [], status: 500}}
      end)

      exception =
        assert_raise Sanity.Error, ~R'%Finch.Response{', fn ->
          Sanity.query("*") |> Sanity.request(@request_config)
        end

      assert exception == %Sanity.Error{
               source: %Finch.Response{body: "fail!", headers: [], status: 500}
             }
    end

    test "timeout error" do
      Mox.expect(MockFinch, :request, fn %Finch.Request{}, Sanity.Finch, _ ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      assert_raise Sanity.Error,
                   "%Mint.TransportError{reason: :timeout}",
                   fn ->
                     Sanity.query("*") |> Sanity.request(@request_config)
                   end
    end

    test "retries and succeeds" do
      Mox.expect(MockFinch, :request, fn %Finch.Request{}, Sanity.Finch, _ ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      Mox.expect(MockFinch, :request, fn %Finch.Request{}, Sanity.Finch, _ ->
        {:ok, %Finch.Response{body: "fail!", headers: [], status: 500}}
      end)

      Mox.expect(MockFinch, :request, fn %Finch.Request{}, Sanity.Finch, _ ->
        {:ok, %Finch.Response{body: "{}", headers: [], status: 200}}
      end)

      log =
        ExUnit.CaptureLog.capture_log([level: :warn], fn ->
          assert {:ok, %Sanity.Response{body: %{}, headers: [], status: 200}} =
                   Sanity.query("*")
                   |> Sanity.request(
                     Keyword.merge(@request_config, max_attempts: 3, retry_delay: 10)
                   )
        end)

      assert log =~
               ~s'retrying failed request in 10ms\n%Mint.TransportError{reason: :timeout}'

      assert log =~
               ~s'retrying failed request in 20ms\n%Finch.Response{'
    end

    test "retries and fails" do
      Mox.expect(MockFinch, :request, fn %Finch.Request{}, Sanity.Finch, _ ->
        {:ok, %Finch.Response{body: "fail!", headers: [], status: 500}}
      end)

      Mox.expect(MockFinch, :request, fn %Finch.Request{}, Sanity.Finch, _ ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      log =
        ExUnit.CaptureLog.capture_log([level: :warn], fn ->
          assert_raise Sanity.Error, "%Mint.TransportError{reason: :timeout}", fn ->
            Sanity.query("*")
            |> Sanity.request(Keyword.merge(@request_config, max_attempts: 2, retry_delay: 5))
          end
        end)

      assert log =~
               ~s'retrying failed request in 5ms\n%Finch.Response{'
    end
  end

  test "request!" do
    Mox.expect(MockFinch, :request, fn %Finch.Request{}, Sanity.Finch, _ ->
      {:ok,
       %Finch.Response{
         body: "{\"error\":{\"description\":\"The mutation(s) failed...\"}}",
         status: 409
       }}
    end)

    assert_raise Sanity.Error,
                 "%Sanity.Response{body: %{\"error\" => %{\"description\" => \"The mutation(s) failed...\"}}, headers: [], status: 409}",
                 fn ->
                   Sanity.mutate([]) |> Sanity.request!(@request_config)
                 end
  end

  describe "stream" do
    test "opts[:drafts] == :exclude (default)" do
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" => "*[(!(_id in path('drafts.**')))] | order(_id) [0..999] { ... }"
               }

        %Response{body: %{"result" => [%{"_id" => "a"}]}}
      end)

      Sanity.stream(request_module: MockSanity, request_opts: @request_config) |> Enum.to_list()
    end

    test "opts[:drafts] == :include" do
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" => "*[] | order(_id) [0..999] { ... }"
               }

        %Response{body: %{"result" => [%{"_id" => "a"}]}}
      end)

      Sanity.stream(drafts: :include, request_module: MockSanity, request_opts: @request_config)
      |> Enum.to_list()
    end

    test "opts[:drafts] == :only" do
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" => "*[(_id in path('drafts.**'))] | order(_id) [0..999] { ... }"
               }

        %Response{body: %{"result" => [%{"_id" => "a"}]}}
      end)

      Sanity.stream(drafts: :only, request_module: MockSanity, request_opts: @request_config)
      |> Enum.to_list()
    end

    test "opts[:drafts] == :invalid" do
      assert_raise NimbleOptions.ValidationError,
                   "expected :drafts to be in [:exclude, :include, :only], got: :invalid",
                   fn ->
                     Sanity.stream(drafts: :invalid, request_opts: @request_config)
                   end
    end

    test "pagination" do
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" => "*[(!(_id in path('drafts.**')))] | order(_id) [0..4] { ... }"
               }

        results = Enum.map(1..5, &%{"_id" => "doc-#{&1}"})
        %Response{body: %{"result" => results}}
      end)

      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" =>
                   "*[(!(_id in path('drafts.**'))) && (_id > $pagination_last_id)] | order(_id) [0..4] { ... }",
                 "$pagination_last_id" => "\"doc-5\""
               }

        results = Enum.map(6..8, &%{"_id" => "doc-#{&1}"})
        %Response{body: %{"result" => results}}
      end)

      assert Sanity.stream(
               batch_size: 5,
               request_module: MockSanity,
               request_opts: @request_config
             )
             |> Enum.to_list() == [
               %{"_id" => "doc-1"},
               %{"_id" => "doc-2"},
               %{"_id" => "doc-3"},
               %{"_id" => "doc-4"},
               %{"_id" => "doc-5"},
               %{"_id" => "doc-6"},
               %{"_id" => "doc-7"},
               %{"_id" => "doc-8"}
             ]
    end

    test "query, projection, and variables options" do
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, request_opts ->
        assert query_params == %{
                 "$type" => "\"page\"",
                 "query" =>
                   "*[(_type == $type) && (!(_id in path('drafts.**')))] | order(_id) [0..999] { _id, title }"
               }

        assert request_opts[:max_attempts] == 3

        %Response{body: %{"result" => [%{"_id" => "a", "title" => "home"}]}}
      end)

      result =
        Sanity.stream(
          projection: "{ _id, title }",
          query: "_type == $type",
          request_module: MockSanity,
          request_opts: @request_config,
          variables: %{type: "page"}
        )
        |> Enum.to_list()

      assert result == [%{"_id" => "a", "title" => "home"}]
    end

    test "unpermitted variable name" do
      assert_raise ArgumentError, "variable names not permitted: [:pagination_last_id]", fn ->
        Sanity.stream(request_opts: @request_config, variables: %{pagination_last_id: ""})
      end

      assert_raise ArgumentError, "variable names not permitted: [\"pagination_last_id\"]", fn ->
        Sanity.stream(request_opts: @request_config, variables: %{"pagination_last_id" => ""})
      end
    end
  end

  test "update_asset" do
    assert Sanity.upload_asset("mydata") == %Request{
             body: "mydata",
             endpoint: :assets,
             method: :post,
             path_params: %{asset_type: :image},
             query_params: %{}
           }

    assert Sanity.upload_asset("vid", [asset_type: :file, content_type: "video/mp4"],
             filename: "cat.mp4"
           ) == %Request{
             body: "vid",
             endpoint: :assets,
             headers: [{"content-type", "video/mp4"}],
             method: :post,
             path_params: %{asset_type: :file},
             query_params: %{"filename" => "cat.mp4"}
           }

    assert_raise NimbleOptions.ValidationError,
                 "expected :asset_type to be in [:image, :file], got: nil",
                 fn ->
                   Sanity.upload_asset("mydata", asset_type: nil)
                 end
  end
end
