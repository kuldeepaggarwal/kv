defmodule KV.Registry do
  use GenServer

  ## Client API

  @doc """
  Starts a reigstry with the given `name`.
  """
  def start_link(name) do
    # 1. Pass the name to GenServer's init
    GenServer.start_link __MODULE__, name, name: name
  end

  @doc """
  Looks up the bucket pid for `name` stored in `server`.

  Returns `{:ok, pid}` if the bucket exists, `:error` otherwise.
  """
  def lookup(server, name) when is_atom(server) do
    # 2. Lookup is now done directly in ETS, without accessing the server
    case :ets.lookup(server, name) do
      [{^name, bucket_pid}] -> {:ok, bucket_pid}
      [] -> :error
    end
  end

  @doc """
  Stops the registry.
  """
  def stop(server) do
    GenServer.stop(server)
  end

  ## Server API

  @doc """
  Ensures there is a bucket associated to the given `name` in `server`.
  """
  def create(server, name) do
    GenServer.call(server, {:create, name})
  end

  def init(table) do
    # 3. We have replaced the names map by the ETS table
    names = :ets.new(table, [:named_table, read_concurrency: true])
    refs = %{}
    {:ok, {names, refs}}
  end

  # 4. The previous handle_call callback for lookup was removed

  def handle_call({:create, name}, _from, {names, refs}) do
    # 5. Read and write to the ETS table instead of the map
    case lookup(names, name) do
      {:ok, bucket_pid} ->
        {:reply, bucket_pid, {names, refs}}
      :error ->
        {:ok, bucket_pid} = KV.Bucket.Supervisor.start_bucket
        ref = Process.monitor(bucket_pid)
        refs = Map.put(refs, ref, name)
        :ets.insert(names, {name, bucket_pid})
        {:reply, bucket_pid, {names, refs}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
     # 6. Delete from the ETS table instead of the map
    {name, refs} = Map.pop(refs, ref)
    :ets.delete(names, name)
    {:noreply, {names, refs}}
  end

  def handle_info(msg, state) do
    super(msg, state)
  end
end
