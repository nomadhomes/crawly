defmodule Crawly.RequestsStorage.Backend do
  @moduledoc """
  The Requests Storage Behaviour module.
  """

  @typedoc """
  The state persisted in `Crawly.RequestsStorage.Worker`. Contains the
  spider name, the crawler id, and any other info required by the backend.
  """

  @type state :: map()
  @type stats :: {:stored_requests, pos_integer()}

  @doc """
  Create the initial backend `state`
  """
  @callback init(state()) :: state()

  @doc """
  Get the current request from the storage.
  """
  @callback pop(state()) :: {Crawly.Request.t(), state()}

  @doc """
  Push the request to the storage.
  """
  @callback store(state(), Crawly.Request.t()) :: state()

  @callback stats(state()) :: stats()
end
