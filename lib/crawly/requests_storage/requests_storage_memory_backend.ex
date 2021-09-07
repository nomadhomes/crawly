defmodule Crawly.RequestsStorage.MemoryBackend do
  @doc """
  This backend for `Crawly.RequestsStorage.Backend` stores the request in memory.
  """

  @behaviour Crawly.RequestsStorage.Backend

  @impl true
  def init(state) do
    Map.merge(state, %{count: 0, requests: []})
  end

  @impl true
  def store(state, request) do
    state
    |> Map.update(:count, 0, &(&1 + 1))
    |> Map.update(:requests, [], &[request | &1])
  end

  @impl true
  def pop(%{requests: requests, count: cnt} = state) do
    {request, rest, new_cnt} =
      case requests do
        [] -> {nil, [], 0}
        [request] -> {request, [], 0}
        [request | rest] -> {request, rest, cnt - 1}
      end

    {request, %{state | requests: rest, count: new_cnt}}
  end

  @impl true
  def stats(%{count: count}) do
    {:stored_requests, count}
  end
end
