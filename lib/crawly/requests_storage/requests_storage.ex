defmodule Crawly.RequestsStorage do
  @moduledoc """
  Request storage, a module responsible for storing urls for crawling

                 ┌──────────────────┐
                 │                  │             ┌------------------┐
                 │ RequestsStorage  <─────────────┤ From crawlers1,2 │
                 │                  │             └------------------┘
                 └─────────┬────────┘
                           │
                           │
                           │
                           │
              ┌────────────▼─────────────────┐
              │                              │
              │                              │
              │                              │
  ┌───────────▼──────────┐       ┌───────────▼──────────┐
  │RequestsStorageWorker1│       │RequestsStorageWorker2│
  │      (Crawler1)      │       │      (Crawler2)      │
  └──────────────────────┘       └──────────────────────┘

  All requests are going through one RequestsStorage process, which
  quickly finds the actual worker, which finally stores the request
  afterwords.

  ## Pluggable Backends

  By default, the requests will be stored in memory using `Crawly.RequestsStorage.MemoryBackend`.
  This approach is easy to use and fast, but have some drawbacks such as not supporting restarts
  and distributing between nodes.

  The storage backend can be customized with a module adhering to the `Crawly.RequestsStorage.Backend`
  behaviour. The backend can be configured as following:

  ```
  config :crawly, :requests_storage_backend, MyApp.CustomBackend
  ```

  """
  require Logger

  use GenServer

  defstruct workers: %{}, pid_spiders: %{}

  alias Crawly.RequestsStorage

  @batch_call_max_count 50

  @doc """
  Store individual request or multiple requests in related child worker
  """
  @spec store(Crawly.spider(), Crawly.Request.t() | [Crawly.Request.t()]) ::
          :ok | {:error, :storage_worker_not_running}
  def store(spider_name, %Crawly.Request{} = request),
    do: GenServer.call(__MODULE__, {:store, {spider_name, [request]}})

  def store(spider_name, requests) when is_list(requests) do
    requests
    |> Stream.chunk_every(@batch_call_max_count)
    |> Enum.each(&GenServer.call(__MODULE__, {:store, {spider_name, &1}}))
  end

  def store(_spider_name, request) do
    Logger.error("#{inspect(request)} does not seem to be a request. Ignoring.")
    {:error, :not_request}
  end

  @doc """
  Pop a request out of requests storage
  """
  @spec pop(Crawly.spider()) ::
          nil | Crawly.Request.t() | {:error, :storage_worker_not_running}
  def pop(spider_name) do
    GenServer.call(__MODULE__, {:pop, spider_name})
  end

  @doc """
  Get statistics from the requests storage
  """
  @spec stats(Crawly.spider()) ::
          {:stored_requests, non_neg_integer()}
          | {:error, :storage_worker_not_running}
  def stats(spider_name) do
    GenServer.call(__MODULE__, {:stats, spider_name})
  end

  @doc """
  Starts a worker for a given spider
  """
  @spec start_worker(Crawly.spider(), crawl_id :: String.t()) ::
          {:ok, pid()} | {:error, :already_started}
  def start_worker(spider_name, crawl_id) do
    GenServer.call(__MODULE__, {:start_worker, spider_name, crawl_id})
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:ok, %RequestsStorage{}}
  end

  def handle_call({:store, {spider_name, requests}}, _from, state) do
    %{workers: workers} = state

    msg =
      case Map.get(workers, spider_name) do
        nil ->
          {:error, :storage_worker_not_running}

        pid ->
          Crawly.RequestsStorage.Worker.store(pid, requests)
      end

    {:reply, msg, state}
  end

  def handle_call({:pop, spider_name}, _from, state = %{workers: workers}) do
    resp =
      case Map.get(workers, spider_name) do
        nil ->
          {:error, :storage_worker_not_running}

        pid ->
          Crawly.RequestsStorage.Worker.pop(pid)
      end

    {:reply, resp, state}
  end

  def handle_call({:stats, spider_name}, _from, state) do
    msg =
      case Map.get(state.workers, spider_name) do
        nil ->
          {:error, :storage_worker_not_running}

        pid ->
          Crawly.RequestsStorage.Worker.stats(pid)
      end

    {:reply, msg, state}
  end

  def handle_call({:start_worker, spider_name, crawl_id}, _from, state) do
    case Map.get(state.workers, spider_name) do
      nil ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            Crawly.RequestsStorage.WorkersSup,
            %{
              id: :undefined,
              restart: :temporary,
              start:
                {Crawly.RequestsStorage.Worker, :start_link,
                 [spider_name, crawl_id]}
            }
          )

        Process.monitor(pid)

        new_workers = Map.put(state.workers, spider_name, pid)
        new_spider_pids = Map.put(state.pid_spiders, pid, spider_name)

        new_state = %{
          state
          | workers: new_workers,
            pid_spiders: new_spider_pids
        }

        {:reply, {:ok, pid}, new_state}

      _ ->
        {:reply, {:error, :already_started}, state}
    end
  end

  # Clean up worker
  def handle_info({:DOWN, _ref, :process, pid, _}, state) do
    spider_name = Map.get(state.pid_spiders, pid)
    new_pid_spiders = Map.delete(state.pid_spiders, pid)
    new_workers = Map.delete(state.workers, spider_name)
    new_state = %{state | workers: new_workers, pid_spiders: new_pid_spiders}

    {:noreply, new_state}
  end
end
