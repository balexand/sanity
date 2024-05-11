defmodule SanityTest do
  use ExUnit.Case, async: true
  doctest Sanity

  import Mox
  setup :verify_on_exit!

  alias Sanity.{MockReq, MockSanity, Request, Response}
  alias NimbleOptions.ValidationError

  @request_config [
    dataset: "myset",
    http_options: [receive_timeout: 1],
    project_id: "projectx",
    req_mod: MockReq,
    token: "supersecret"
  ]

  test "mutate" do
    assert %Request{
             body: body,
             endpoint: :mutate,
             method: :post,
             query_params: %{"returnIds" => true}
           } =
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

    assert Jason.decode!(body) == %{
             "mutations" => [%{"create" => %{"_type" => "product", "title" => "Test product"}}]
           }
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
      Mox.expect(MockReq, :request, fn opts ->
        assert Enum.sort(opts) == [
                 body: nil,
                 headers: [{"authorization", "Bearer supersecret"}],
                 method: :get,
                 receive_timeout: 1,
                 url:
                   "https://projectx.api.sanity.io/v2021-10-21/data/query/myset?%24var_2=%22y%22&query=%2A"
               ]

        {:ok, %Req.Response{body: %{}, headers: %{}, status: 200}}
      end)

      assert {:ok, %Response{body: %{}, headers: %{}, status: 200}} ==
               Sanity.query("*", var_2: "y")
               |> Sanity.request(@request_config)
    end

    test "with CDN URL" do
      Mox.expect(MockReq, :request, fn opts ->
        assert Keyword.fetch!(opts, :url) ==
                 "https://projectx.apicdn.sanity.io/v2021-10-21/data/query/myset?query=%2A"

        {:ok, %Req.Response{body: %{}, headers: %{}, status: 200}}
      end)

      assert {:ok, %Response{body: %{}, headers: %{}, status: 200}} ==
               Sanity.query("*")
               |> Sanity.request(Keyword.put(@request_config, :cdn, true))
    end

    test "options validations" do
      query = Sanity.query("*")

      assert_raise ValidationError,
                   "invalid value for :dataset option: expected string, got: :ok",
                   fn ->
                     Sanity.request(query, dataset: :ok, project_id: "abc")
                   end

      assert_raise ValidationError,
                   "invalid value for :http_options option: expected keyword list, got: %{}",
                   fn ->
                     Sanity.request(query,
                       dataset: "production",
                       http_options: %{},
                       project_id: "abc"
                     )
                   end

      assert_raise ValidationError,
                   "invalid value for :project_id option: expected string, got: 1",
                   fn ->
                     Sanity.request(query, dataset: "production", project_id: 1)
                   end

      assert_raise ValidationError, ~r{required :dataset option not found}, fn ->
        Sanity.request(query, Keyword.delete(@request_config, :dataset))
      end
    end

    test "409 response" do
      Mox.expect(MockReq, :request, fn _opts ->
        {:ok,
         %Req.Response{
           body: %{"error" => %{"description" => "The mutation(s) failed..."}},
           status: 409
         }}
      end)

      assert Sanity.mutate([]) |> Sanity.request(@request_config) == {
               :error,
               %Sanity.Response{
                 body: %{"error" => %{"description" => "The mutation(s) failed..."}},
                 status: 409
               }
             }
    end

    test "414 response" do
      Mox.expect(MockReq, :request, fn _ ->
        {:ok,
         %Req.Response{
           status: 414,
           body:
             "<html>\r\n<head><title>414 Request-URI Too Large</title></head>\r\n<body>\r\n<center><h1>414 Request-URI Too Large</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>\r\n"
         }}
      end)

      exception =
        assert_raise Sanity.Error, fn ->
          Sanity.query("*") |> Sanity.request(@request_config)
        end

      assert exception == %Sanity.Error{
               source: %Req.Response{
                 status: 414,
                 body:
                   "<html>\r\n<head><title>414 Request-URI Too Large</title></head>\r\n<body>\r\n<center><h1>414 Request-URI Too Large</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>\r\n"
               }
             }
    end

    test "5xx response" do
      Mox.expect(MockReq, :request, fn _ ->
        {:ok, %Req.Response{body: "fail!", headers: %{}, status: 500}}
      end)

      exception =
        assert_raise Sanity.Error, ~r'#Req.Response<', fn ->
          Sanity.query("*") |> Sanity.request(@request_config)
        end

      assert exception == %Sanity.Error{
               source: %Req.Response{body: "fail!", headers: %{}, status: 500}
             }
    end

    test "timeout error" do
      Mox.expect(MockReq, :request, fn _ ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      assert_raise Sanity.Error,
                   "%Mint.TransportError{reason: :timeout}",
                   fn ->
                     Sanity.query("*") |> Sanity.request(@request_config)
                   end
    end
  end

  test "request!" do
    Mox.expect(MockReq, :request, fn _ ->
      {:ok,
       %Req.Response{
         body: %{"error" => %{"description" => "The mutation(s) failed..."}},
         status: 409
       }}
    end)

    assert_raise Sanity.Error,
                 ~r'%Sanity.Response{body:',
                 fn ->
                   Sanity.mutate([]) |> Sanity.request!(@request_config)
                 end
  end

  describe "stream" do
    test "opts[:drafts] == :exclude (default)" do
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" => "*[] | order(_id) [0..999] { ... }",
                 "perspective" => "published"
               }

        %Response{body: %{"result" => [%{"_id" => "a"}]}}
      end)

      Sanity.stream(request_module: MockSanity, request_opts: @request_config) |> Enum.to_list()
    end

    test "opts[:perspective]" do
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" => "*[] | order(_id) [0..999] { ... }",
                 "perspective" => "previewDrafts"
               }

        %Response{body: %{"result" => [%{"_id" => "a"}]}}
      end)

      Sanity.stream(
        perspective: "previewDrafts",
        request_module: MockSanity,
        request_opts: @request_config
      )
      |> Enum.to_list()
    end

    test "opts[:variables] invalid" do
      assert_raise NimbleOptions.ValidationError,
                   "invalid value for :variables option: expected map, got: []",
                   fn ->
                     Sanity.stream(request_opts: @request_config, variables: [])
                   end

      assert_raise NimbleOptions.ValidationError,
                   ~r{invalid map in :variables option: expected map key to match at least one given type},
                   fn ->
                     Sanity.stream(request_opts: @request_config, variables: %{1 => ""})
                   end
    end

    test "pagination" do
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" => "*[] | order(_id) [0..4] { ... }",
                 "perspective" => "published"
               }

        results = Enum.map(1..5, &%{"_id" => "doc-#{&1}"})
        %Response{body: %{"result" => results}}
      end)

      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _ ->
        assert query_params == %{
                 "query" => "*[(_id > $pagination_last_id)] | order(_id) [0..4] { ... }",
                 "perspective" => "published",
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
      Mox.expect(MockSanity, :request!, fn %Request{query_params: query_params}, _request_opts ->
        assert query_params == %{
                 "$type" => "\"page\"",
                 "query" => "*[(_type == $type)] | order(_id) [0..999] { _id, title }",
                 "perspective" => "published"
               }

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
                 "invalid value for :asset_type option: expected one of [:image, :file], got: nil",
                 fn ->
                   Sanity.upload_asset("mydata", asset_type: nil)
                 end
  end
end
