defmodule DurableServer.ObjectStoreReadinessTest do
  use ExUnit.Case, async: true

  alias DurableServer.ObjectStore

  test "returns a transport error with a binary reason from a bucket readiness check" do
    reason = "request process exited before returning a response"
    store = object_store(%Req.TransportError{reason: reason})

    assert {:error, %Req.TransportError{reason: ^reason}} =
             ObjectStore.ensure_bucket_exists(store)
  end

  test "retries an ambiguous create and accepts an existing bucket" do
    reason = "request process exited before returning a response"

    store =
      object_store([
        %Req.TransportError{reason: reason},
        %Req.Response{status: 409}
      ])

    assert :ok = ObjectStore.ensure_bucket_exists(store)
    assert_receive {:request, %Req.Request{method: :put}}
    assert_receive {:request, %Req.Request{method: :put}}
  end

  defp object_store(responses) when is_list(responses) do
    parent = self()
    responses = start_supervised!({Agent, fn -> responses end})

    adapter = fn request ->
      send(parent, {:request, request})
      response = Agent.get_and_update(responses, fn [response | rest] -> {response, rest} end)
      {request, response}
    end

    new_object_store(adapter)
  end

  defp object_store(response) do
    adapter = fn request -> {request, response} end
    new_object_store(adapter)
  end

  defp new_object_store(adapter) do
    ObjectStore.new(
      bucket: "test-bucket",
      access_key_id: "test-access-key",
      secret_access_key: "test-secret-key",
      s3_endpoint: "http://s3.test",
      default_region: "us-east-1",
      req_opts: [adapter: adapter, retry_delay: 0, retry_log_level: false]
    )
  end
end
