defmodule Crawly.RequestsStorage.Worker do
  @moduledoc """
  Requests Storage, is a module responsible for storing requests for a given
  spider.

  Automatically filters out already seen requests (uses `fingerprints` approach
  to detect already visited pages).

  Pipes all requests through a list of middlewares, which do pre-processing of
  all requests before storing them
  """
  require Logger

  use GenServer

  defstruct spider_name: nil, crawl_id: nil, provider: nil

  alias Crawly.RequestsStorage.Worker

  @doc """
  Store individual request or multiple requests
  """
  @spec store(Crawly.spider(), Crawly.Request.t() | [Crawly.Request.t()]) :: :ok
  def store(pid, %Crawly.Request{} = request), do: store(pid, [request])

  def store(pid, requests) when is_list(requests) do
    do_call(pid, {:store, requests})
  end

  @doc """
  Pop a request out of requests storage
  """
  @spec pop(pid()) :: Crawly.Request.t() | nil
  def pop(pid) do
    do_call(pid, :pop)
  end

  @doc """
  Get statistics from the requests storage
  """
  @spec stats(pid()) :: {:stored_requests, non_neg_integer()}
  def stats(pid) do
    do_call(pid, :stats)
  end

  def start_link(spider_name, crawl_id) do
    GenServer.start_link(__MODULE__, [spider_name, crawl_id])
  end

  def init([spider_name, crawl_id]) do
    Logger.metadata(spider_name: spider_name, crawl_id: crawl_id)

    Logger.debug(
      "Starting requests storage worker for #{inspect(spider_name)}..."
    )

    provider =
      Crawly.Utils.get_settings(
        :requests_storage_backend,
        spider_name,
        Crawly.RequestsStorage.MemoryBackend
      )

    state = %Worker{
      spider_name: spider_name,
      crawl_id: crawl_id,
      provider: provider
    }

    {:ok, provider.init(state)}
  end

  # Store the given requests
  def handle_call({:store, requests}, _from, state) do
    new_state = Enum.reduce(requests, state, &pipe_request/2)
    {:reply, :ok, new_state}
  end

  # Get current request from the storage
  def handle_call(:pop, _from, %{provider: provider} = state) do
    {request, state} = provider.pop(state)
    {:reply, request, state}
  end

  def handle_call(:stats, _from, state) do
    %{provider: provider} = state
    {:reply, provider.stats(state), state}
  end

  defp do_call(pid, command) do
    GenServer.call(pid, command)
  catch
    error, reason ->
      Logger.debug(Exception.format(error, reason, __STACKTRACE__))
  end

  defp pipe_request(request, %{provider: provider} = state) do
    case Crawly.Utils.pipe(request.middlewares, request, state) do
      {false, new_state} ->
        new_state

      {new_request, new_state} ->
        # Process request here....
        provider.store(new_state, new_request)
    end
  end
end
