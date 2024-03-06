defmodule Triex.Node do
  @moduledoc "The processing node of a trie."

  # -----
  # types
  # -----

  # outgoing edges are indexed by character for transition
  @typep edgemap() :: %{char() => pid()}

  # ----------------
  # public functions
  # ----------------

  @doc "Start the process with a terminal flag."
  @spec start(bool()) :: pid()
  def start(final?) do
    spawn_link(__MODULE__, :node, [final?, %{}])
  end

  # ---------
  # main loop
  # ---------

  @spec node(bool(), edgemap()) :: no_return()
  def node(final?, edges) do
    receive do
      {exec, {:match, <<>>}} ->
        # empty string at terminal node is success
        # empty string at non-terminal node is failure
        send(exec, {:result, final?})

      {exec, {:match, <<c::utf8, rest::binary>>}} when is_map_key(edges, c) ->
        # next character has a valid transition
        send(Map.fetch!(edges, c), {exec, {:match, rest}})

      {exec, {:match, _str}} ->
        # still some unmatched input
        # we are not the final answer
        # there are no more matched transitions, so failure
        send(exec, {:result, false})

      {exec, {:add, <<>>}} ->
        # new terminal state
        # even if it was duplicate of existing terminal state (final?==true)
        send(exec, {:add, :ok})
        node(true, edges)

      {exec, {:add, <<c::utf8, rest::binary>>}} when is_map_key(edges, c) ->
        # existing path, just propagate the add request
        send(Map.fetch!(edges, c), {exec, {:add, rest}})

      {exec, {:add, <<c::utf8, rest::binary>>}} ->
        # no existing path, spawn a new node
        pid = start(rest == <<>>)
        new_edges = Map.put(edges, c, pid)
        # continue traversal to the new node
        send(pid, {exec, {:add, rest}})
        node(final?, new_edges)

      {exec, {:dump, str}} ->
        # return this node info
        send(exec, {:node, str, final?, Map.keys(edges)})
        # propagate through all the outgoing edges
        Enum.each(edges, fn {c, pid} ->
          send(pid, {exec, {:dump, <<str::binary, c::utf8>>}})
        end)

      any ->
        throw({:unhandled_message, [__MODULE__, any]})
    end

    node(final?, edges)
  end
end
