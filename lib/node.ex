defmodule Triex.Node do
  @moduledoc "The processing node of a trie."

  # -----
  # types
  # -----

  # outgoing edges are indexed by character for transition
  @typep edgemap() :: %{char() => pid()}

  # each node has a single parent with an incoming edge (except root)
  @typep revedge() :: E.maybe({char(), pid()})

  # ----------------
  # public functions
  # ----------------

  @doc "Start the process with a terminal flag and a parent reference."
  @spec start(bool(), revedge()) :: pid()
  def start(final?, revedge \\ nil) do
    # pass the parent to the new node
    spawn_link(__MODULE__, :init, [final?, revedge])
  end

  # initialize and set process state
  @spec init(bool(), revedge()) :: no_return()
  def init(final?, revedge) do
    # Process.flag(:trap_exit, true)
    node(final?, %{}, revedge)
  end

  # ---------
  # main loop
  # ---------

  @spec node(bool(), edgemap(), revedge()) :: no_return()
  def node(final?, edges, rev) do
    receive do
      # match ----------

      {exec, {:match, <<>>}} ->
        # empty string at terminal node is success
        # empty string at non-terminal node is failure
        send(exec, {:matched, final?})

      {exec, {:match, <<c::utf8, rest::binary>>}} when is_map_key(edges, c) ->
        # next character has a valid transition
        send(Map.fetch!(edges, c), {exec, {:match, rest}})

      {exec, {:match, _str}} ->
        # still some unmatched input
        # we are not the final answer
        # there are no more matched transitions, so failure
        send(exec, {:matched, false})

      # add reverse ----------
      # build truncated tree from reversed strings

      # {exec, {:add_rev, _, _}} when final? ->
      #   # final suffix of the current word already exists
      #   # so immediately stop the traversal
      #   send(exec, {:add_rev, :ignore})

      # {exec, {:add_rev, <<c::utf8>>, tail}} ->
      #   # new suffix state
      #   self = self()
      #   # stop before the final state (final? always false)
      #   suffix = IO.chardata_to_string(tail)
      #   # return a suffix-pid pair for the suffix index, with final true
      #   send(exec, {:add_rev, suffix, self})
      #   # add the final node to block future traversals
      #   # kill these nodes after construction 
      #   pid = start(true, {c, self})
      #   node(final?, Map.put(edges, c, pid), rev)

      # {exec, {:add_rev, <<c::utf8, rest::binary>>, tail}} when is_map_key(edges,c) ->
      #   # existing path, just propagate the add_rev request
      #   send(Map.fetch!(edges, c), {exec, {:add_rev, rest, [c|tail]}})

      # {exec, {:add_rev, <<c::utf8, rest::binary>>, tail}} ->
      #   # no existing path, spawn a new non-final node
      #   pid = start(false, {c,self()})
      #   # continue traversal to the new node
      #   send(pid, {exec, {:add_rev, rest, [c|tail]}})
      #   node(final?, Map.put(edges, c, pid), rev)

      # reverse ----------
      # convert the reverse tree into a forward suffix forest

      # {exec, :reverse} when final? ->
      #   # final states were only to block during reverse construction
      #   # they can be pruned now
      #   # only the non-final suffix entry-points will be used
      #   send( exec, :reverse)
      #   exit(:normal)

      # {_exec, :reverse}=msg when is_nil(rev) ->
      #   # root, propagate to children
      #   Enum.each(edges, fn {_, pid} -> send(pid, msg) end)
      #   # change to final, all future traversals will finish here
      #   node(true, %{}, nil)

      # {_exec, :reverse} = msg ->
      #   # normal suffix node, propagate to children
      #   Enum.each(edges, fn {_, pid} -> send(pid, msg) end)
      #   # swap the reverse edge to parent into the forward direction
      #   node(final?, Map.new([rev]), nil)

      # add forward ----------
      # build the forward tree over a map of suffixes

      # {_exec, {:add_for, <<>>, _}} ->
      #   # should not reach here
      #   # all final states should be in the suffixes
      #   IO.puts("Illegal final state")
      #   raise RuntimeError, message: "Illegal final state"

      # {exec, {:add_for, <<c::utf8, _::binary>>=suf, sufmap}=ev} when is_map_key(sufmap, suf) ->
      #   IO.inspect(ev)
      #   # remaining suffix is in the map
      #   # just reference it and terminate traversal
      #   send(exec, {:add_for, :ok})
      #   sufpid = Map.fetch!(sufmap, suf)
      #   node(false, Map.put(edges, c, sufpid), nil)

      # {exec, {:add_for, <<c::utf8, rest::binary>>, sufmap}=ev} when is_map_key(edges, c) ->
      #    IO.inspect(ev)
      #   # existing path, just propagate the add request
      #   pid = Map.fetch!(edges, c)
      #   send(pid, {exec, {:add_for, rest, sufmap}})

      # {exec, {:add_for, <<c::utf8, rest::binary>>, sufmap}=ev} when rest != "" ->
      #    IO.inspect(ev)
      #   # no existing path, spawn a new node
      #   # new node is never final, because all finals are in suffixes
      #   pid = start(false)
      #   # continue traversal to the new node
      #   send(pid, {exec, {:add_for, rest, sufmap}})
      #   node(false, Map.put(edges, c, pid), nil)

      # add ----------
      # original single-pass tree-based constructor

      {exec, {:add, <<c::utf8, rest::binary>>, sink}} when is_map_key(edges, c) ->
        # existing path, just propagate the add request
        send(Map.fetch!(edges, c), {exec, {:add, rest, sink}})

      {exec, {:add, <<c::utf8>>, sink}} ->
        # last link goes to the sink, so end traversal
        send(exec, {:add, :ok})
        node(final?, Map.put(edges, c, sink), rev)

      {exec, {:add, <<c::utf8, rest::binary>>, sink}} ->
        # no existing path, spawn a new node
        pid = start(false)
        # continue traversal to the new node
        send(pid, {exec, {:add, rest, sink}})
        node(final?, Map.put(edges, c, pid), rev)

      {exec, {:add, <<>>, _sink}} ->
        # new final node within existing structure
        send(exec, {:add, :ok})
        node(true, edges, rev)

      # dump ----------
      # output metrics and diagrams

      {exec, {:dump, str}} ->
        # return this node info
        send(exec, {:node, Exa.Process.iself(), str, final?, edges})
        # propagate through all the outgoing edges
        Enum.each(edges, fn {c, pid} ->
          send(pid, {exec, {:dump, <<str::binary, c::utf8>>}})
        end)

      any ->
        throw({:unhandled_message, [__MODULE__, any]})
    end

    node(final?, edges, rev)
  end
end
